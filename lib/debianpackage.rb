# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'binarypackage'

class DebianPackage < BinaryPackage

  def do_pack
    puts meta_data + "\n"
  end

  def meta_data
    meta = String.new
    meta += "Package: #{@name}\n"
    meta += "Version: #{@version}\n"
    meta += "Source: #{@source}\n"
    meta += "Maintainer: #{@maintainer}\n"
    meta += "Section: #{@section}\n"
    meta += "Architecture: %s\n" % \
      (@is_arch_indep == 'true' ? 'all' : DebianPackage.debian_architecture)

    if not @requires.empty?
      requires = @requires.sort do |a, b|
        a[0] <=> b[0]
      end

      meta += "Depends: " + \
      requires.collect do |pkg,version|
        version = "= #{@version}" if version == '=='
        if version
          "#{pkg} (#{version})"
        else
          pkg
        end
      end\
      .join(', ')
      meta += "\n"
    end

    meta += "Description: #{@description.summary}\n"
    full_description = @description.full_description
    meta += "#{full_description}\n" unless full_description.empty?
    return meta
  end

  def self.debian_architecture
    errmsg = "failed to detect machine architecture."

    march = `uname -m`.chomp
    if $? != 0: raise StandardError errmsg end

    case march
      when /i.86/
        'i386'
      when /x86-64/
        'amd64'
      when /arm/
        'arm'
      else
        raise StandardError errmsg
      end
  end

end

