# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'rubygems'
require 'nokogiri'
require 'libarchive_ruby'
require 'popen'
require 'packagedescription'

class SourcePackage

  def initialize(xml_config)
    case xml_config
      when Nokogiri::XML::Element
        source_node = xml_config
      when String
        source_node = Nokogiri::XML(xml_config).root
      else
        raise RuntimeError
    end

    # general info about source package
    @name = source_node['name']
    @description = PackageDescription.new(source_node.at_xpath('description'))

    # build dependencies
    @requires = source_node.xpath('requires/package').collect do |pkg_node|
      [ pkg_node['name'], pkg_node['version'] ]
    end

    # patches to the sources
    @patches = []
    source_node.xpath('patches/patchset').each do |patch_set|
      next if not [ 'any' ].include? patch_set['arch']
      @patches << patch_set.xpath('file').collect {|file| file['src']}
    end

    # original package sources
    @sources = source_node.xpath('sources/file').collect {|file| file['src']}

    @rules = {}
    source_node.xpath('rules/*').select{|node| node.element?}.each do |node|
      @rules[node.name] = node.content
    end
  end

  def unpack(source_dir = '.')
    @sources.each do |src_name|
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
    puts "patch"
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

