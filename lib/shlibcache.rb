# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'binpackage'
require 'popen'

class ShlibCache

  module DpkgInterface

    def which_package_provides(filename)
      result = nil
      cmd = "dpkg -S #{File.expand_path(filename)}"
        exit_status = Popen.popen2(cmd) do |stdin, stdeo|
        stdin.close
        result = stdeo.read.split(':', 2)[0]
      end
      if exit_status != 0:
        return nil
      else
        return result.strip
      end
    end

    def version_of_package(package_name)
      result = nil
      cmd = "dpkg-query -W --showformat '${Version}' #{package_name}"
      exit_status = Popen.popen2(cmd) do |stdin, stdeo|
        stdin.close
        result = stdeo.read
      end

      # TODO: proper error reporting
      return nil if exit_status != 0

      # extract components, we need epoch and upstream version
      version = result.match(/^(?:(\d+):)?([-.+~a-zA-Z0-9]+?)(?:-([.~+a-zA-Z0-9]+)){0,1}$/)
      epoch, upstream, release = version[1,4]

      unless epoch.nil?
        return "#{epoch}:#{upstream}"
      else
        return "#{upstream}"
      end
    end

  end

  class SharedObject

    def self.system_package_manager
      [ 'dpkg', 'opkg', 'rpm' ].each do |packager_name|
        [ '/usr/bin/', '/usr/sbin', '/bin', '/sbin' ].each do |path|
          if File.exist?(path + '/' + packager_name): return packager_name end
        end
      end
      return 'unknown'
    end

    def initialize(lib_path, lib_attributes)
      @lib_path = lib_path
      @lib_attributes = lib_attributes
      @package_name = nil
      @package_version = nil

      if self.class.system_package_manager == 'dpkg'
        self.extend ShlibCache::DpkgInterface
      else
        raise StandardError \
          "System uses unknown or unsupported package manager."
      end
    end

    def package_name
      if @package_name.nil?
        @package_name = which_package_provides @lib_path
      else
        @package_name
      end
    end

    def package_version
      if @package_version.nil?
        @package_version = version_of_package package_name
      else
        @package_version
      end
    end

    def package_name_and_version
      return package_name, package_version
    end

  end

  def initialize
    @map = {}
    Popen.popen2('/sbin/ldconfig -p') do |stdin, stdeo|
      re = /^\s*(\S+) \((.*)\) => (\S+)/
      stdin.close
      stdeo.each_line do |line|
        match = re.match(line)
        next if match.nil?
        lib_name = match[1]
        lib_attr = match[2].split(/,/).collect { |s| s.strip }
        lib_path = match[3]
        @map[lib_name] = SharedObject.new(lib_path, lib_attr)
      end
    end
  end

end
