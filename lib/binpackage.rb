# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'popen'
require 'filemagic'

class BinaryPackage
  include FileMagic

  attr_reader :contents, :name, :version
  attr_accessor :base_dir, :output_dir

  FILE_TYPE  = 0
  FILE_PERMS = 1
  FILE_OWNER = 2
  FILE_GROUP = 3

  def initialize(xml_config)
    case xml_config
      when Nokogiri::XML::Element
        bin_node = xml_config
      when String
        bin_node = Nokogiri::XML(xml_config).root
      else
        raise RuntimeError
    end

    @base_dir = 'xpack/tmp-install'
    @output_dir = '..'

    # general info about binary package
    @name = bin_node['name']
    @summary = bin_node.at_xpath('summary').content.strip
    @description = bin_node.at_xpath('description')
    @maintainer = bin_node['maintainer'] + ' <' + bin_node['email'] + '>'
    @version = bin_node['version'] + '-' + bin_node['revision']
    @section = bin_node['section'] || 'unknown'
    @source = bin_node['source']
    @is_arch_indep = bin_node['architecture-independent']

    # binary dependencies
    @requires = bin_node.xpath('requires/package').collect do |pkg_node|
      [ pkg_node['name'], pkg_node['version'] ]
    end
    @requires.sort! do |a, b|
      a[0] <=> b[0]
    end

    # contents specification
    @content_spec = {}
    bin_node.xpath('contents/*').each do |node|
      src = node['src'].strip
      @content_spec[src] = [ node.name, node['mode'], node['owner'], node['group'] ]
    end

    @base_dir = 'pack/tmp-install'
    @output_dir = '..'
  end

  def pack
    generate_file_list
    strip_debug_symbols
    do_pack 
  end

  def generate_file_list
    additional_contents = {}

    # clone content specification
    @contents = @content_spec.clone

    # generate complete listing
    @contents.each_pair do |src, attributes|
      type_of_file = attributes[FILE_TYPE]
      mode  = attributes[FILE_PERMS]
      owner = attributes[FILE_OWNER]
      group = attributes[FILE_GROUP]
      listing = []
      real_path = File.expand_path(@base_dir + '/' + src)
      case type_of_file
        when 'dir'
          # we don't have to do anything for dir entries
        when 'file'
          if real_path =~ /(\*|\?)/
            listing = Dir[real_path]
          elsif File.directory?(real_path)
            real_path.slice! /\/$/
            listing = Dir[real_path + '/**/*']
          else
            attributes[FILE_TYPE] = file_type(real_path)
         end
      end

      listing.each do |entry|
        type_of_file = file_type(entry)
        entry.slice! /^#{Regexp.escape(@base_dir)}/
        unless @contents.has_key? entry
          additional_contents[entry] = [ type_of_file, mode, owner, group ]
        end
      end
    end

    # delete globs
    @contents.delete_if { |entry, attributes| entry =~ /(\*|\?)/ }

    # merge new contents
    @contents.merge! additional_contents

    # sort contents
    @contents = @contents.sort do |a,b|
      a[0] <=> b[0]
    end

    return @contents
  end

  def strip_debug_symbols
    # create base_dir/usr/lib/debug
    [ 'usr', 'lib', 'debug' ].inject('') do |path, dir|
      File.exist?(@base_dir + '/' + path + '/' + dir) or
        Dir.mkdir(@base_dir + '/' + path + '/' + dir)
      path += "/#{dir}"
    end

    # strip unstripped, dynamic objects
    @contents.each do |entry|
      file_path = entry[0]
      real_path = @base_dir + '/' + file_path
      debug_path = @base_dir + '/usr/lib/debug/' + file_path
      type_of_file = entry[1][FILE_TYPE]
      if is_dynamic_object? type_of_file

        # don't strip again
        unless File.exist?(File.dirname(debug_path))
          # create directory, if necessary
          dir_list = File.dirname(file_path)\
            .split('/')\
            .delete_if { |s| s.empty? }
          dir_list.inject('') do |path, dir|
            File.exist?(@base_dir + '/usr/lib/debug/' + path + '/' + dir) or
              Dir.mkdir(@base_dir + '/usr/lib/debug/' + path + '/' + dir)
            path += "/#{dir}"
          end
        end

        # separate debug information
        cmd_list = [
          "objcopy --only-keep-debug #{real_path} #{debug_path}",
          "objcopy --strip-unneeded #{real_path}",
          "objcopy --add-gnu-debuglink=#{debug_path} #{real_path}"
        ]
        cmd_list.each do |cmd|
          Popen.popen2(cmd) do |stdin, stdeo|
            stdin.close
            stdeo.each_line do |line|
              puts line
            end
          end
        end
      end
    end
  end

  def shlib_deps

  end

end

