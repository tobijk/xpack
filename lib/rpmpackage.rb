# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'binpackage'

class RPMPackage < BinaryPackage

  def do_pack
    raise StandardError "RPM packaging is not implemented."
  end

  private

  def meta_data
  end

  def rpm_architecture
  end

end

