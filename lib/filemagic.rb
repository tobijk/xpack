# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

module FileMagic

  def file_type?(real_path)
    file_type = `file #{real_path}`.split(':', 2)[1].strip
    return file_type.start_with?('ERROR') ? '' : file_type
  end

end
