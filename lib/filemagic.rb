# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

module FileMagic

  def file_type(path)
    file_type = `file #{path}`.split(':', 2)[1].strip
    return file_type.start_with?('ERROR') ? '' : file_type
  end

  def is_dynamic_object?(file_type)
    match_executable = /ELF \d+-bit LSB executable.*, dynamically linked.*, not stripped/
    match_library = /ELF \d+-bit LSB shared object.*, dynamically linked.*, not stripped/

    case file_type
      when match_executable, match_library
        return true
      else
        return false
    end
  end

  def arch_word_size(file_type)
    match_elf_obj = /ELF (\d+)-bit LSB.*/
    match = file_type.match(match_elf_obj)
    if match
      return match[1]
    else
      return nil
    end
  end

end
