# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'dpkg'

class PackageManager

  @@instance = nil

  def self.instance
    @@instance = system_package_manager.new if @@instance.nil?
    return @@instance
  end

  def self.system_package_manager
    [ 'dpkg', 'opkg' ].each do |packager_name|
      ENV['PATH'].split(':').each do |path|
        if File.exist?(path + '/' + packager_name)
          return Kernel.const_get(packager_name.capitalize)
        end
      end
    end

    raise StandardError, "system uses unknown or unsupported package manager"
  end

  private_class_method :new
end
