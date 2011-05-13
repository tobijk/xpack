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
require 'basepackage'

class BinaryPackage < BasePackage
  attr_reader :contents, :name, :version, :base_dir, :output_dir

  class EntryAttributes
    attr_accessor :src, :type, :mode, :owner, :group, :conffile

    alias :conffile? :conffile

    def initialize(spec = {})
      @type     = spec[:type]
      @mode     = spec[:mode]
      @owner    = spec[:owner] || 'root'
      @group    = spec[:group] || 'root'
      @conffile = spec[:conffile]
    end
  end

  def initialize(xml_config, parms = {})
    parms = { :debug_pkgs => true }.merge(parms)

    case xml_config
      when Nokogiri::XML::Element
        bin_node = xml_config
      when String
        bin_node = Nokogiri::XML(xml_config).root
      else
        raise RuntimeError
    end

    # general info about binary package
    @name = bin_node['name']
    @description = PackageDescription.new(bin_node.at_xpath('description'))
    @maintainer = bin_node['maintainer'] + ' <' + bin_node['email'] + '>'
    @version = (bin_node['epoch'].to_i > 0 ? "#{bin_node['epoch']}:" : '') + \
      bin_node['version'] + \
      (bin_node['revision'] ? "-#{bin_node['revision']}" : "")
    @section = bin_node['section'] || 'unknown'
    @source = bin_node['source']
    @is_arch_indep = \
      bin_node['architecture-independent'] == 'true' ? true : false

    # whether to generate debug packages
    @make_debug_pkgs = parms[:debug_pkgs]

    # binary dependencies
    @relations = {}
    [ 'requires', 'provides', 'conflicts', 'replaces' ].each do |dep_type|
      dep_node = bin_node.at_xpath("#{dep_type}")
      @relations[dep_type] = BasePackage::DependencySpecification.from_xml(dep_node)
    end

    # contents specification
    @content_spec = {}
    bin_node.xpath('contents/*').each do |node|
      src = node['src'].strip
      @content_spec[src] = EntryAttributes.new(
        :type     => node.name,
        :mode     => node['mode'],
        :owner    => node['owner'],
        :group    => node['group'],
        :conffile => node['conffile']
      )
    end

    # maintainer scripts
    @maintainer_scripts = {}
    bin_node.xpath('maintainer-scripts/*').each do |node|
      if [ 'preinst', 'postinst', 'prerm', 'postrm' ].include? node.name
        @maintainer_scripts[node.name] = "#!/bin/sh -e\n" + node.content
      end
    end

    @base_dir = 'pack/tmp-install'
    @output_dir = '..'
  end

  def epoch_and_upstream_version
    # extract components, we need epoch and upstream version
    version = @version.match(/^(?:(\d+):)?([-.+~a-zA-Z0-9]+?)(?:-([.~+a-zA-Z0-9]+)){0,1}$/)
    epoch, upstream, release = version[1,4]

    unless epoch.nil?
      return "#{epoch}:#{upstream}"
    else
      return "#{upstream}"
    end
  end

  def base_dir=(base_dir)
    @base_dir = File.expand_path(base_dir) if base_dir
  end

  def output_dir=(output_dir)
    @output_dir = File.expand_path(output_dir) if output_dir
  end

  def prepare
    generate_file_list
    strip_debug_symbols
  end

  def pack(shlib_cache)
    shlib_deps(shlib_cache)
    do_pack 
  end

  def generate_file_list
    additional_contents = {}

    # clone content specification
    @contents = @content_spec.clone

    # generate complete listing
    @contents.each_pair do |src, attr|
      type_of_file = attr.type
      mode = attr.mode
      owner = attr.owner
      group = attr.group
      conffile = attr.conffile?

      listing = []

      # due to expand_path we never have a trailing '/'
      real_path = File.expand_path(@base_dir + '/' + src)
      case type_of_file
        when 'dir'
          attr.type = 'directory'
        when 'file'
          if real_path =~ /(\*|\?)/
            listing = Dir[real_path]
          elsif File.directory?(real_path)
            real_path.slice! /\/$/
            listing = Dir[real_path + '/**/*']
          else
            attr.type = FileMagic.file_type(real_path)
         end
      end

      listing.each do |entry|
        type_of_file = FileMagic.file_type(entry)
        entry.slice! /^#{Regexp.escape(@base_dir)}/
        unless @contents.has_key? entry
          additional_contents[entry] = EntryAttributes.new(
            :type => type_of_file,
            :mode => mode,
            :owner => owner,
            :group => group,
            :conffile => type_of_file.start_with?('directory') ?\
              false : conffile
          )
        end
      end
    end

    # delete globs
    @contents.delete_if { |entry, attr| entry =~ /(\*|\?)/ }

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

    # strip unstripped objects
    @contents.each do |src, attr|
      real_path = @base_dir + '/' + src
      debug_path = @base_dir + '/usr/lib/debug/' + src
      if FileMagic.unstripped? attr.type

        # create directory, if necessary
        dir_list = File.dirname(src)\
          .split('/')\
          .delete_if { |s| s.empty? }
        dir_list.inject('') do |path, dir|
          File.exist?(@base_dir + '/usr/lib/debug/' + path + '/' + dir) or
            Dir.mkdir(@base_dir + '/usr/lib/debug/' + path + '/' + dir)
          path += "/#{dir}"
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

      end #if
    end
  end

  def shlib_deps(shlib_cache)
    @contents.each do |src, attr|
      type_of_file = attr.type
      next unless FileMagic.is_dynamic_object? type_of_file
      arch_word_size = FileMagic.arch_word_size type_of_file

      cmd = "objdump -p #{@base_dir + '/' + src}"
      Popen.popen2(cmd) do |stdin, stdeo|

        stdin.close
        stdeo.each_line do |line|
          match = line.match(/NEEDED\s+(\S+)/)
          next if match.nil?
          lib_name = match[1]
          shlib_cache[lib_name].each do |shared_obj|
            if shared_obj.arch_word_size == arch_word_size
              pkg, version = shared_obj.package_name_and_version
              # don't overwrite existing entries and don't add pkg itself
              if @relations['requires'][pkg].nil? && pkg != @name
                @relations['requires'][pkg] =\
                  BasePackage::Dependency.new(pkg, ">= #{version}")
              end
            end
          end 
        end

      end #popen2
    end 
  end

end

