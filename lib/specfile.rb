# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'nokogiri'
require 'time'

module Specfile

  RELAXNG_SCHEMA_FILE = File.expand_path(
    File.dirname(__FILE__) + '/../relaxng/xpack.rng.xml')

  class ValidationError < RuntimeError
  end

  class << self

    def load(xml_spec_file_name)
      xml_doc = nil

      File.open(xml_spec_file_name, 'r:utf-8') do |fp|
        begin
          xml_doc = Nokogiri::XML(fp) do |config|
            config.strict.noent.nocdata.dtdload.xinclude
          end
        rescue Nokogiri::XML::SyntaxError => e
          msg = "->#{" Line #{e.line}:" if e.line != 0} #{e.message}"
          raise RuntimeError, "broken spec file: parse errors\n#{msg}"
        end
      end

      validate_structure(xml_doc)
      validate_format(xml_doc)

      return xml_doc
    end

    def validate_structure(xml_doc)
      schema = Nokogiri::XML::RelaxNG.new(
        File.open(RELAXNG_SCHEMA_FILE, 'r:utf-8'))

      errors = schema.validate(xml_doc)

      unless errors.empty?
        errors = errors.collect do |e|
          "->#{" Line #{e.line}:" if e.line != 0} #{e.message}"
        end
        errors = errors.join("\n").chomp
        raise ValidationError, "invalid spec file: syntax errors\n#{errors}"
      end
    end

    def validate_format(xml_doc)
      errors = []

      err_msg = Proc.new { |node, regex|
        msg  = "-> Line #{node.line}: #{node.parent.name}/@#{node.name} "
        msg += "\"#{node.content}\", doesn't adhere to specification\n"
        msg += "-> #{regex.inspect}"
      }

      specification = [
        [ "//*[name() = 'source' or name() = 'package']/@name", /^[a-zA-Z0-9]*(?:(?:\+|-|\.)[a-zA-Z0-9]*)*$/ ],
        [ "//binary//package/@version", /(?:^(?:<<|<=|=|>=|>>)\s*(?:(\d+):)?([-.+~a-zA-Z0-9]+?)(?:-([.~+a-zA-Z0-9]+)){0,1}$)|(?:^==$)/ ],
        [ "//source//package/@version", /(?:^(?:<<|<=|=|>=|>>)\s*(?:(\d+):)?([-.+~a-zA-Z0-9]+?)(?:-([.~+a-zA-Z0-9]+)){0,1}$)/ ],
        [ "//changelog/release/@epoch", /^\d+$/ ],
        [ "//changelog/release/@version", /^([-.+~a-zA-Z0-9]+?)(?:-([.~+a-zA-Z0-9]+)){0,1}$/ ],
        [ "//changelog/release/@revision", /^[.~+a-zA-Z0-9]+$/ ],
        [ "//changelog/release/@email", /^[-_%.a-zA-Z0-9]+@[-.a-z0-9]+\.[a-z]{2,4}$/ ],
        [ "//changelog/release/@date", /^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+(?:((?:-|\+)\d{4})|(?:(?:GMT|UTC)(?:(?:-|\+)\d{1,2}))|[a-zA-Z]+)$/ ]
      ]

      specification.each do |xpath, regex|
        xml_doc.xpath(xpath).each do |node|
          errors << err_msg.call(node, regex) unless node.content =~ regex
        end
      end

      begin
        Time.parse(xml_doc.at_xpath("//changelog/release/@date").content)
      rescue ArgumentError => e
        errors << "-> //changelog/release/@date: #{e.message}"
      end

      unless errors.empty?
        errors = errors.join("\n").chomp
        raise ValidationError, "invalid spec file:\n#{errors}"
      end
    end

  end
end
