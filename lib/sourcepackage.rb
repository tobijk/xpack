# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'rubygems'
require 'nokogiri'
require 'libarchive_rs'
require 'popen'
require 'packagedescription'
require 'basepackage.rb'
require 'fileutils'
require 'platform'

class SourcePackage < BasePackage
  attr_accessor :base_dir, :patches, :rules, :sources

  def initialize(xml_config)
    case xml_config
      when Nokogiri::XML::Element
        source_node = xml_config
      when String
        source_node = Nokogiri::XML(xml_config).root
      else
        raise RuntimeError
    end

    @base_dir = '.'

    # general info about source package
    @name = source_node['name']
    @description = PackageDescription.new(source_node.at_xpath('description'))

    # build dependencies
    @relations = {}
    dep_node = source_node.at_xpath('requires')
    @relations['requires'] =\
      BasePackage::DependencySpecification.from_xml(dep_node)

    # patches to the sources
    @patches = []
    source_node.xpath('patches/patchset').each do |patch_set|
      @patches += patch_set.xpath('file').collect { |file|
        [ file['src'], patch_set['subdir'].to_s ]
      }
    end

    # original package sources
    @sources = source_node.xpath('sources/file').collect { |file|
      [ file['src'], file['subdir'].to_s ]
    }

    @maintainer = source_node['maintainer'] + ' <' + source_node['email'] + '>'

    @rules = {}
    source_node.xpath('rules/*').select{|node| node.element?}.each do |node|
      @rules[node.name] = node.content
    end
  end

  def missing_build_dependencies
    @relations['requires'].unfulfilled_dependencies
  end

  def build_dependencies
    @relations['requires']
  end

  def unpack(source_dir = '.')
    @sources.each do |src_name, subdir|
      # rebase to source package folder
      src_name = File.expand_path(@base_dir + '/' + src_name) \
        unless src_name.start_with? '/'

      # create subdir if necessary
      source_dir_and_subdir = File.expand_path(source_dir + '/' + subdir)
      FileUtils.makedirs(source_dir_and_subdir) \
        unless File.exist?(source_dir_and_subdir)

      # check if file is there
      unless File.file? src_name
        raise RuntimeError, "package file '#{src_name}' not found"
      end

      Archive.read_open_filename(src_name) do |archive|
        while entry = archive.next_header
          pathname = entry.pathname
          pathname.slice!(/^\/?[^\/]*\//)
          next if pathname.empty?

          full_path = source_dir_and_subdir + '/' + pathname
          puts "#{entry.pathname} -> #{full_path}"

          if entry.directory?
            FileUtils.makedirs(full_path) unless File.directory? full_path
          elsif entry.symbolic_link?
            File.symlink(entry.symlink, full_path)
          elsif entry.file?
            # tar does this implicitely, as well
            dirname = File.dirname(full_path)
            FileUtils.makedirs(dirname) if not File.exist?(dirname)
            # extract file contents
            File.open(full_path, 'wb+') do |fp|
              archive.read_data(1024) {|data| fp.write(data)}
            end
          else
            msg = "file type of '#{entry.pathname}' is not allowed"
            raise RuntimeError, msg
          end
          File.chmod(entry.mode, full_path) unless entry.symbolic_link? 
        end
      end
    end
  end

  def patch(source_dir = '.')
    @patches.each do |patch_file, subdir|
      patch_file = File.expand_path(@base_dir + '/' + patch_file)\
        unless patch_file.start_with? '/'

      e_source_dir = \
        if subdir.empty? then source_dir else source_dir + '/' + subdir end

      puts cmd = "patch -f -p1 -d #{e_source_dir} -i #{patch_file}"
      exit_code = Popen.popen2(cmd) do |stdin, stdeo|
        stdin.close
        stdeo.each_line { |line| puts line }
      end

      raise RuntimeError, "patch failed to apply" unless exit_code == 0
    end
  end

  def meta_data(mode = 'normal')
    meta = String.new
    meta += "Source: #{@name}\n"
    meta += "Priority: optional\n"
    meta += "Maintainer: #{@maintainer}\n"
    meta += "Build-depends: #{self.build_dependencies}\n"

    return meta
  end

  ['prepare', 'build', 'install', 'clean'].each do |name|
    class_eval %{
      def #{name}(env = {})
        # env setup
        num_parallel_jobs = (Platform.num_cpus * 1.5).to_i.to_s
        env.merge! Platform.build_flags
        env['XPACK_PARALLEL_JOBS'] = ENV['XPACK_PARALLEL_JOBS'] || num_parallel_jobs

        # execute task
        exit_code = Popen.popen2("/bin/sh -e -x -s", env) do |stdin, stdeo|
          stdin.write(@rules['#{name}'])
          stdin.close
          stdeo.each_line do |line|
            puts line
          end
        end
        if exit_code != 0
          raise RuntimeError, "could not #{name} \#{@name}"
        end
      end
    }
  end

end

