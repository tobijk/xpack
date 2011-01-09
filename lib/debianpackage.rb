# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'binarypackage'
require 'digest/md5'

class DebianPackage < BinaryPackage

  def do_pack
    package_file_name = @name + '_' + @version.sub(/^\d+:/, '') + \
      '_' + debian_architecture + '.deb'
    package_file_name = File.expand_path(@output_dir + '/' + package_file_name)

    puts package_file_name
    puts meta_data
  end

  def debian_binary
    return "2.0\n"
  end

  def meta_data
    meta = String.new
    meta += "Package: #{@name}\n"
    meta += "Version: #{@version}\n"
    meta += "Source: #{@source}\n"
    meta += "Maintainer: #{@maintainer}\n"
    meta += "Section: #{@section}\n"
    meta += "Architecture: #{debian_architecture}\n"

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

  def md5sums
    result = ""

    @contents.each do |entry|
      file_path = entry[0]
      real_path = @base_dir + '/' + file_path

      next unless File.file? real_path

      begin
        md5 = Digest::MD5.new
        File.open(real_path, 'r') do |fp|
          while buf = fp.read(1024)
            md5.update(buf)
          end
        end
        result << "#{md5.hexdigest}  #{file_path.sub(/^\//, '')}\n"
      rescue Exception => e
        msg = "Error while generating md5sum for '#{file_path}': #{e.message}"
        raise RuntimeError msg
      end
    end

    return result
  end

  def debian_architecture
    return 'all' if @is_arch_indep
    errmsg = "failed to detect machine architecture."
    march = `uname -m`.chomp
    if $? != 0 then raise StandardError errmsg end
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

