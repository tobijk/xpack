# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

module FileMagic

  def self.file_type(path)
    file_type = `file #{path}`.split(':', 2)[1].strip
    return file_type.start_with?('ERROR') ? '' : file_type
  end

  def self.unstripped?(file_type)
    match_unstripped_elf = /ELF \d+-bit LSB .*, .* linked.*, .*not stripped/

    case file_type
      when match_unstripped_elf
        return true
      else
        return false
    end
  end

  def self.is_dynamic_object?(file_type)
    match_executable = /ELF \d+-bit LSB executable.*, dynamically linked.*/
    match_library = /ELF \d+-bit LSB shared object.*, dynamically linked.*/

    case file_type
      when match_executable, match_library
        return true
      else
        return false
    end
  end

  def self.points_to_dynamic_object?(symlink)
    file = fully_resolve_symlink(symlink)
    return is_dynamic_object?(FileMagic.file_type file)
  end

  def self.fully_resolve_symlink(symlink)
    return symlink unless File.symlink? symlink

    file = File.expand_path(symlink)
    while File.symlink?(file)
      dirname = File.dirname(file)
      file = File.readlink(file)
      if file =~ /^\//
        file = File.expand_path(file)
      else
        file = File.expand_path(dirname + '/' + file)
      end
    end

    return file
  end

  def self.arch_word_size(file_type)
    match_elf_obj = /ELF (\d+)-bit LSB.*/
    match = file_type.match(match_elf_obj)
    if match
      return match[1]
    else
      return nil
    end
  end

end
