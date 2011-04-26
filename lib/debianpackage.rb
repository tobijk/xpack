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
    pack_package()
    pack_package("debug") if @make_debug_pkgs
  end

  def pack_package(mode = "normal")
    debug_suffix = mode == "debug" ? '-dbg_' : '_'
    package_file_name = @name + debug_suffix + @version.sub(/^\d+:/, '') + \
      '_' + debian_architecture + '.deb'
    package_file_name = File.expand_path(@output_dir + '/' + package_file_name)

    contents = {}
    meta_data = ""

    # find debug symbols
    if mode == "debug"
      @contents.each do |src, attr|
        debug_file = File.expand_path('/usr/lib/debug/' + src)
        next unless File.file? @base_dir + '/' + debug_file

        # add entry for debug data
        contents[debug_file] =\
          BinaryPackage::EntryAttributes.new(
            :type => attr.type,
            :mode => 0644,
            :owner => 'root',
            :group => 'root',
            :conffile => false
          )

        # we need to include the directories
        dir_list = File.dirname(src).gsub(/^\//, '').split(/\//)
        dir_list.inject('/usr/lib/debug') do |path, dir|
          path = path + '/' + dir
          unless contents[path]
            contents[path] = BinaryPackage::EntryAttributes.new(
              :type => 'directory',
              :mode => 0755,
              :owner => 'root',
              :group => 'root',
              :conffile => false
            )
          end
          path
        end
      end
      return if contents.empty? # don't assemble unless debug data available
      contents = contents.sort
      meta_data = meta_data('debug')
    else
      contents = @contents
      meta_data = meta_data()
    end

    assemble_package(meta_data, contents, package_file_name)
  end

  def assemble_package(meta_data, contents, outfile)
    Dir.mktmpdir do |tmpdir|

      write_data_tar_gz(contents, tmpdir + '/data.tar.gz')
      write_control_tar_gz(meta_data, contents, tmpdir + '/control.tar.gz')
      File.open(tmpdir + '/debian-binary', 'w+') { |f| f.write(debian_binary) }

      ar = Archive.write_open_filename(outfile,
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
            File.open(real_path) { |fp| ar.write_data { fp.read(4096) } }
          end
        end
      end

    end
  end

  def write_control_tar_gz(meta_data, pkg_contents, outfile)
    ar = Archive.write_open_filename(outfile, Archive::COMPRESSION_GZIP,
      Archive::FORMAT_TAR_USTAR) do |ar|

      ctrl_contents = [
        [ 'control', meta_data, 0644 ],
        [ 'md5sums', md5sums(pkg_contents), 0644 ],
      ]
      @maintainer_scripts.each_pair { |k, v| ctrl_contents << [ k, v, 0754 ] }

      conffiles = conffiles(pkg_contents)
      ctrl_contents << [ 'conffiles', conffiles, 0644 ] unless conffiles.empty?

      ctrl_contents.each do |entry_name, entry_content, mode|
        ar.new_entry do |ar_entry|
          ar_entry.mode = Archive::ENTRY_FILE | mode
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

  def write_data_tar_gz(pkg_contents, outfile)
    ar = Archive.write_open_filename(outfile, Archive::COMPRESSION_GZIP,
      Archive::FORMAT_TAR_USTAR) do |ar|

      pkg_contents.each do |src, attr|
        file_path  = '.' + src
        file_type  = attr.type
        file_mode  = attr.mode
        file_mode  = file_mode.oct if file_mode.class == String
        file_owner = attr.owner
        file_group = attr.group
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

  def meta_data(mode = 'normal')
    meta = String.new
    meta += mode == 'normal' ? "Package: #{@name}\n" : "Package: #{@name}-dbg\n"
    meta += "Version: #{@version}\n"
    meta += "Source: #{@source}\n"
    meta += "Maintainer: #{@maintainer}\n"
    meta += "Section: #{@section}\n"
    meta += "Architecture: #{debian_architecture}\n"

    dep_type_2_str = {
      'requires'  => 'Depends: ',
      'provides'  => 'Provides: ',
      'conflicts' => 'Conflicts: ',
      'replaces'  => 'Replaces: '
    }

    if mode == 'normal'
      [ 'requires', 'provides', 'conflicts', 'replaces' ].each do |dep_type|
        if not eval "@#{dep_type}.empty?"
          pkg_list = eval "@#{dep_type}.sort { |a, b| a[0] <=> b[0] }"

          meta += dep_type_2_str[dep_type] + \
          pkg_list.collect do |pkg,version|
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
      end
    else
      meta += "Depends: #{@name} (= #{@version})\n"
    end

    if mode == 'normal'
      meta += "Description: #{@description.summary}\n"
      full_description = @description.full_description
      meta += "#{full_description}\n" unless full_description.empty?
    else
      meta += "Description: debug symbols for binaries in package '#{@name}'\n"
    end

    return meta
  end

  def md5sums(contents)
    result = ""

    contents.each do |src, attr|
      real_path = @base_dir + '/' + src
      next unless File.file? real_path
      begin
        md5 = Digest::MD5.new
        File.open(real_path, 'r') do |fp|
          while buf = fp.read(1024)
            md5.update(buf)
          end
        end
        result << "#{md5.hexdigest}  #{src.sub(/^\//, '')}\n"
      rescue Exception => e
        msg = "Error while generating md5sum for '#{src}': #{e.message}"
        raise RuntimeError msg
      end
    end

    return result
  end

  def conffiles(contents)
    result = ""

    contents.each do |src, attr|
      next if attr.type == "directory" || attr.conffile == false

      real_path = @base_dir + '/' + src
      next unless File.file? real_path

      attr.conffile = true if attr.conffile.nil? && src.start_with?('/etc/')
      next unless attr.conffile

      result << src + "\n"
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

