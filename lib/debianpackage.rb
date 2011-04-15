# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'tmpdir'
require 'binarypackage'
require 'digest/md5'
require 'libarchive_rs'

class DebianPackage < BinaryPackage

  def do_pack
    package_file_name = @name + '_' + @version.sub(/^\d+:/, '') + \
      '_' + debian_architecture + '.deb'
    package_file_name = File.expand_path(@output_dir + '/' + package_file_name)

    Dir.mktmpdir do |tmpdir|
      write_data_tar_gz(tmpdir + '/data.tar.gz')
      write_control_tar_gz(tmpdir + '/control.tar.gz')
      File.open(tmpdir + '/debian-binary', 'w+') do |f|
        f.write(debian_binary)
      end

      ar = Archive.write_open_filename(package_file_name,
        Archive::COMPRESSION_NONE, Archive::FORMAT_AR_SVR4) do |ar|

        [ 'debian-binary', 'control.tar.gz',
            'data.tar.gz' ].each do |entry_name|
          ar.new_entry do |ar_entry|
            real_path = tmpdir + '/' + entry_name
            ar_entry.copy_stat(real_path)
            ar_entry.mode = Archive::ENTRY_FILE | 0644
            ar_entry.pathname = entry_name
            ar_entry.uid = 0
            ar_entry.gid = 0
            ar_entry.uname = 'root'
            ar_entry.gname = 'root'
            ar.write_header(ar_entry)
            File.open(real_path) { |fp| ar.write_data { fp.read(1024) } }
          end
        end

      end
    end
  end

  def write_control_tar_gz(path)

    ar = Archive.write_open_filename(path, Archive::COMPRESSION_GZIP,
      Archive::FORMAT_TAR_USTAR) do |ar|

      contents = [
        [ 'control', meta_data ],
        [ 'md5sums', md5sums   ]
      ]

      contents.each do |entry_name, entry_content|
        ar.new_entry do |ar_entry|
          ar_entry.mode = Archive::ENTRY_FILE | 0644
          ar_entry.pathname = entry_name
          ar_entry.atime = Time.now.to_i
          ar_entry.mtime = Time.now.to_i
          ar_entry.uid = 0
          ar_entry.gid = 0
          ar_entry.uname = 'root'
          ar_entry.gname = 'root'
          ar_entry.size = entry_content.bytesize
          ar.write_header(ar_entry)
          ar.write_data(entry_content)
        end
      end

    end
  end

  def write_data_tar_gz(path)

    ar = Archive.write_open_filename(path, Archive::COMPRESSION_GZIP,
      Archive::FORMAT_TAR_USTAR) do |ar|

      @contents.each do |entry_name, attributes|
        file_path  = '.' + entry_name
        file_type  = attributes[BinaryPackage::FILE_TYPE ]
        file_mode  = attributes[BinaryPackage::FILE_PERMS]
        file_mode  = file_mode.oct if file_mode.class == String
        file_owner = attributes[BinaryPackage::FILE_OWNER]
        file_group = attributes[BinaryPackage::FILE_GROUP]
        real_path  = File.expand_path(@base_dir + '/' + file_path)
 
        begin
          ar.new_entry do |ar_entry|
            if file_type == 'directory' && !File.exists?(real_path)
              ar_entry.mode = Archive::ENTRY_DIRECTORY | 0755
              ar_entry.atime = Time.now.to_i
              ar_entry.mtime = Time.now.to_i
            else
              ar_entry.copy_stat(real_path)
            end
            ar_entry.mode = ar_entry.filetype | file_mode if file_mode
            ar_entry.pathname = file_path
            ar_entry.uname = file_owner ? file_owner : 'root'
            ar_entry.gname = file_group ? file_group : 'root'
            ar.write_header(ar_entry)

            if ar_entry.file?
              File.open(real_path) { |fp| ar.write_data { fp.read(1024) } }
            end
          end
        rescue Exception => e
          raise StandardError, "error packaging '#{file_path}': #{e.message}\n"
        end
      end

    end
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

