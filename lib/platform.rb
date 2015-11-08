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

  CONFIG_GUESS = '/usr/share/misc/config.guess'

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
        File.open('/proc/cpuinfo', 'r:utf-8') do |f|
          f.each_line do |line|
            num_cpus += 1 if line =~ /processor\s*:\s*\d+/
          end
        end
      end

      return num_cpus
    end

    def find_executable(executable_name)
      search_path = (
        ENV['PATH'].split(':') + ['/bin', '/sbin', '/usr/bin', '/usr/sbin']
      ).uniq.join(':')

      search_path.split(':').each do |path|
        location = "#{path}/#{executable_name}"
        return location if File.exist? location
      end

      return nil
    end

    def config_guess
      # ask native gcc
      if gcc = find_executable('gcc')
        return `#{gcc} -dumpmachine`.strip
      end

      # try to run 'config.guess'
      return `#{CONFIG_GUESS}`.strip if File.exist? CONFIG_GUESS

      # this is unlikely to happen
      return nil
    end

  end

end
