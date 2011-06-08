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

class SourcePackage < BasePackage
  attr_accessor :base_dir

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
      @patches += patch_set.xpath('file').collect {|file| file['src']}
    end

    # original package sources
    @sources = source_node.xpath('sources/file').collect {|file| file['src']}

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
    @sources.each do |src_name|
      # rebase to source package folder
      src_name = File.expand_path(@base_dir + '/' + src_name) \
        unless src_name.start_with? '/'
      # check if file is there
      unless File.file? src_name
        raise RuntimeError, "package file '#{src_name}' not found"
      end
      Archive.read_open_filename(src_name) do |archive|
        while entry = archive.next_header
          pathname = entry.pathname
          pathname.slice!(/^\/?[^\/]*\//)
          next if pathname.empty?
          full_path = source_dir + '/' + pathname
          puts "#{entry.pathname} -> #{full_path}"
          if entry.directory?
            Dir.mkdir full_path unless File.directory? full_path
          elsif entry.symbolic_link?
            File.symlink(entry.symlink, full_path)
          elsif entry.block_special?
            cmd = "mknod #{full_path} b #{entry.devmajor} #{entry.devminor} 2>&1"
            output = IO.popen(cmd) {|p| p.readlines}
            output = if output.empty? then "" else output[0].chomp end
            if $? != 0
              raise RuntimeError, "error creating block device: " + output
            end
          elsif entry.character_special?
            cmd = "mknod #{full_path} c #{entry.devmajor} #{entry.devminor} 2>&1"
            output = IO.popen(cmd) {|p| p.readlines}
            output = if output.empty? then "" else output[0].chomp end
            if $? != 0
              raise RuntimeError, "error creating char device: " + output
            end
          elsif entry.fifo?
            cmd = "mknod #{full_path} p 2>&1"
            output = IO.popen(cmd) {|p| p.readlines}
            output = if output.empty? then "" else output[0].chomp end
            if $? != 0
              raise RuntimeError, "error creating fifo: " + output
            end
          else
            # seemingly tar does this implicitely, as well
            dirname = File.dirname(full_path)
            FileUtils.makedirs(dirname) if not File.exist?(dirname)

            # retrieve file contents
            File.open(full_path, 'w+') do |fp|
              archive.read_data(1024) {|data| fp.write(data)}
            end
          end
          File.chmod(entry.mode, full_path) unless entry.symbolic_link? 
        end
      end
    end
  end

  def patch(source_dir = '.')
    @patches.each do |p|
      patch_file = File.expand_path(@base_dir + '/' + p)\
        unless p.start_with? '/'

      cmd = "patch -f -p1 -d #{source_dir} -i #{patch_file}"
      exit_code = Popen.popen2(cmd) do |stdin, stdeo|
        stdin.close
        stdeo.each_line { |line| puts line }
      end

      raise RuntimeError, "patch failed to apply" unless exit_code == 0
    end
  end

  ['prepare', 'build', 'install', 'clean'].each do |name|
    class_eval %{
      def #{name}(env = {})
        exit_code = Popen.popen2("/bin/sh -s") do |stdin, stdeo|
          env.each_pair {|k,v| stdin.write("\#{k}=\#{v}\n")}
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

