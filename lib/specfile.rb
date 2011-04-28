# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'nokogiri'

module Specfile

  RELAXNG_SCHEMA_FILE = File.expand_path(
    File.dirname(__FILE__) + '/../relaxng/xpack.rng.xml')

  class ValidationError < RuntimeError
  end

  def self.load(xml_spec_file_name)
    xml_doc = nil

    File.open(xml_spec_file_name, 'r') do |fp|
      begin
        xml_doc = Nokogiri::XML(fp) do |config|
          config.strict.noent.nocdata.dtdload.xinclude
        end
      rescue Exception => e
        raise RuntimeError, "error while loading spec file: #{e.message.chomp}"
      end
    end

    validate_structure(xml_doc)
    return xml_doc
  end

  def self.validate_structure(xml_doc)
    schema = Nokogiri::XML::RelaxNG.new(File.open(RELAXNG_SCHEMA_FILE))

    errors = schema.validate(xml_doc)

    unless errors.empty?
      errors = errors.collect{|e| "-> line #{e.line}: #{e.message}"}.join("\n")
      raise ValidationError, "invalid spec file: syntax errors\n#{errors.chomp}"
    end
  end

end
