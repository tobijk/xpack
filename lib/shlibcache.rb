# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'binarypackage'
require 'popen'
require 'filemagic'
require 'packagemanager'

class ShlibCache

  class SharedObject
    attr_writer :arch_word_size, :package_name, :package_version

    def self.system_package_manager
      [ 'dpkg', 'opkg', 'rpm' ].each do |packager_name|
        [ '/usr/bin/', '/usr/sbin', '/bin', '/sbin' ].each do |path|
          if File.exist?(path + '/' + packager_name) then return packager_name end
        end
      end
      return 'unknown'
    end

    def initialize(lib_path)
      @lib_path = lib_path
      @package_name = nil
      @package_version = nil
      @arch_word_size = nil
      @package_manager = PackageManager.instance
    end

    def package_name
      if @package_name.nil?
        @package_name = @package_manager.which_package_provides @lib_path
      else
        @package_name
      end
    end

    def package_version
      if @package_version.nil?
        @package_version = @package_manager.installed_version_of_package package_name
      else
        @package_version
      end
    end

    def package_name_and_version
      return package_name, package_version
    end

    def arch_word_size
      if @arch_word_size.nil?
        target = FileMagic.fully_resolve_symlink @lib_path
        file_type = FileMagic.file_type target
        @arch_word_size = FileMagic.arch_word_size(file_type)
      else
        @arch_word_size
      end
    end

  end

  def initialize
    @map = Hash.new { |h, k| h[k] = Array.new }

    Popen.popen2('/sbin/ldconfig -p') do |stdin, stdeo|
      re = /^\s*(\S+) \(.*\) => (\S+)/
      stdin.close
      stdeo.each_line do |line|
        match = re.match(line) or next
        lib_name = match[1]
        lib_path = match[2]
        @map[lib_name] << SharedObject.new(lib_path)
      end
    end
  end

  def [](lib_name)
    return @map[lib_name]
  end

  def overlay_package(binary_package)
    base_dir = binary_package.base_dir

    binary_package.contents.each do |src, attr|
      real_path = binary_package.base_dir + '/' + src

      file_type = if File.symlink?(real_path)
        target = FileMagic.fully_resolve_symlink(real_path)
        FileMagic.file_type target
      else
        attr.type
      end
      next unless FileMagic.is_dynamic_object? file_type

      shared_obj = SharedObject.new(src)
      shared_obj.package_name = binary_package.name
      shared_obj.package_version = binary_package.epoch_and_upstream_version
      shared_obj.arch_word_size = FileMagic.arch_word_size file_type

      # retrieve existing entries
      shared_obj_list = @map[File.basename(src)]

      # look if entry exists and overwrite
      shared_obj_list.each_index do |i|
        tmp_shared_obj = shared_obj_list[i]
        if tmp_shared_obj.arch_word_size == shared_obj.arch_word_size
          shared_obj_list[i] = shared_obj
          shared_obj = nil
          break
        end
      end

      # if we didn't replace an entry, add to list
      unless shared_obj.nil?
        shared_obj_list << shared_obj
      end
    end
  end

end
