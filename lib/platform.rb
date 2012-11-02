# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'packagemanager'

class Platform

  class << self

    def build_flags
      build_flags = Hash.new

      # first check if package manager knows
      begin
        build_flags = PackageManager.instance.get_build_flags
      rescue NoMethodError ; end

      return build_flags unless build_flags.empty?

      # then check if gcc, g++ are installed
      ENV['PATH'].split(':').each do |path|
        build_flags['CFLAGS']   = '-g -O2' if File.exist?(path + '/gcc')
        build_flags['CXXFLAGS'] = '-g -O2' if File.exist?(path + '/g++')
      end

      return build_flags
    end

    def num_cpus
      num_cpus = 0

      unless File.exist? '/proc/cpuinfo'
        num_cpus = 1
      else
        File.open('/proc/cpuinfo', 'r') do |f|
          f.each_line do |line|
            num_cpus += 1 if line =~ /processor\s*:\s*\d+/
          end
        end
      end

      return num_cpus
    end

    def find_executable(executable_name)
      ENV['PATH'].split(':').each do |path|
        location = "#{path}/#{executable_name}"
        return location if File.exist? location
      end

      return nil
    end

    def config_guess
      # ask native gcc
      if gcc = find_executable('gcc')
        system_type = nil

        Popen.popen2("#{gcc} -v", {}) do |stdin, stdeo|
          stdin.close
          stdeo.each_line do |line|
            if line =~ /^Target:\s+(\S+)/
              system_type = $1
            end
          end
        end

        return system_type if system_type
      end

      # try to run 'config.guess'
      return `/usr/share/misc/config.guess` if \
        File.exist? '/usr/share/misc/config.guess'

      # this is unlikely to happen
      return nil
    end

  end

end
