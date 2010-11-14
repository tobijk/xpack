# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Manager
# Copyright (C) 2010, Tobias Koch <tobias.koch@gmail.com>
#
# XPack is licensed under the GNU General Public License, version 2. A copy of
# the license text can be found in the file LICENSE included in the source distribution.
#

require 'rubygems'
require 'nokogiri'
require 'srcpackage'
require 'binpackage'

class PackageControl

  def initialize(xml_spec_file_name, parms = {})
    @parms = {
      :outdir => nil,
      :ignore_deps => false,
      :format => :deb
    }.merge(parms)

    xml_doc = nil
    File.open(xml_spec_file_name, 'r') do |fp|
      begin
        xml_doc = Nokogiri::XML(fp) do |config|
          config.strict.noent.nocdata.dtdload.xinclude
        end
      rescue Exception => e
        raise RuntimeError, "Error while loading spec file: #{e.message.chomp}"
      end
    end

    @info = Hash.new

    @info['maintainer'] = [
      xml_doc.at_xpath('/control/info/maintainer/name').content,
      xml_doc.at_xpath('/control/info/maintainer/email').content
    ]

    @defines = {
      'XPACK_SOURCE_DIR'  => 'xpack/tmp-src',
      'XPACK_INSTALL_DIR' => 'xpack/tmp-install'
    }

    xml_doc.xpath('/control/defines/def').each do |node|
      @defines[node['name']] = node['value']
    end

    # if build dir is not set, then build dir is src dir
    @defines['XPACK_BUILD_DIR'] =
      @defines['XPACK_SOURCE_DIR'] unless @defines.has_key? 'XPACK_BUILD_DIR'

    # these have to be absolute paths
    ['SOURCE', 'BUILD', 'INSTALL'].each do |s|
      @defines["XPACK_#{s}_DIR"] = File.expand_path @defines["XPACK_#{s}_DIR"]
    end

    @src_pkg = SourcePackage.new(xml_doc.at_xpath('/control/source'))
  end

  def prepare()
    ['SOURCE', 'BUILD', 'INSTALL'].each do |s|
      directory = @defines["XPACK_#{s}_DIR"]
      File.exist?(directory) or Dir.mkdir directory
    end
    source_dir = @defines['XPACK_SOURCE_DIR']
    @src_pkg.unpack source_dir
    @src_pkg.patch source_dir
    @src_pkg.prepare @defines
  end

  def build()
    build_dir = @defines['XPACK_BUILD_DIR']
    File.exist?(build_dir) or Dir.mkdir build_dir
    @src_pkg.build @defines
  end

  def install()
    install_dir = @defines['XPACK_INSTALL_DIR']
    File.exist?(install_dir) or Dir.mkdir install_dir
    @src_pkg.install @defines
  end

  def package()
    puts "package"
  end

  def default()
    prepare
    build
    install
    package
  end

end

