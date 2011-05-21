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
require 'sourcepackage'
require 'debianpackage'
require 'fileutils'
require 'shlibcache'
require 'specfile'

class PackageControl

  def initialize(xml_spec_file_name, parms = {})
    @parms = {
      :outdir => nil,
      :ignore_deps => false,
      :format => :deb,
      :debug_pkgs => true
    }.merge(parms)

    xml_doc = Specfile.load(xml_spec_file_name)

    @info = Hash.new

    # copy maintainer, email, version, revision to package sections
    [ 'maintainer', 'email', 'epoch', 'version', 'revision' ].each do |attr_name|
      xpath = "/control/changelog/release[1]/@#{attr_name}"
      next unless attr_node = xml_doc.at_xpath(xpath)
      attr_val = attr_node.content.strip
      xpath = "/control/*[name() = 'source' or name() = 'package']"
      xml_doc.xpath(xpath).each do |pkg_node|
        pkg_node[attr_name] = attr_val
      end
    end

    # copy source name and architecture-independent to binary package sections
    xpath = '/control/source/@name'
    source_name = xml_doc.at_xpath(xpath).content.strip
    xpath = '/control/source/@architecture-independent'
    is_arch_indep = begin xml_doc.at_xpath(xpath).content rescue 'false' end
    xml_doc.xpath('/control/package').each do |pkg_node|
      pkg_node['source'] = source_name
      pkg_node['architecture-independent'] = is_arch_indep
    end

    @defines = {
      'XPACK_SOURCE_DIR'  => 'pack/tmp-source',
      'XPACK_INSTALL_DIR' => 'pack/tmp-install'
    }

    @defines['XPACK_BASE_DIR'] = File.expand_path(
      File.dirname(File.expand_path(xml_spec_file_name)) + '/..')

    xml_doc.xpath('/control/defines/def').each do |node|
      @defines[node['name']] = node['value']
    end

    # if build dir is not set, then build dir is src dir
    @defines['XPACK_BUILD_DIR'] =
      @defines['XPACK_SOURCE_DIR'] unless @defines.has_key? 'XPACK_BUILD_DIR'

    # these have to be absolute paths
    ['SOURCE', 'BUILD', 'INSTALL'].each do |s|
      @defines["XPACK_#{s}_DIR"] = \
      if @defines["XPACK_#{s}_DIR"].start_with? '/'
        File.expand_path @defines["XPACK_#{s}_DIR"]
      else
        File.expand_path(@defines['XPACK_BASE_DIR'] + '/' + @defines["XPACK_#{s}_DIR"])
      end
    end

    @src_pkg = SourcePackage.new(xml_doc.at_xpath('/control/source'))
    @src_pkg.base_dir = @defines['XPACK_BASE_DIR']

    @bin_pkgs = xml_doc.xpath('/control/package').collect do |node|
      pkg = case @parms[:format]
        when :deb
          DebianPackage.new(node, :debug_pkgs => @parms[:debug_pkgs])
      end
      pkg.base_dir = @defines['XPACK_INSTALL_DIR']
      pkg.output_dir = @parms[:outdir] ? File.expand_path(@parms[:outdir]) : nil
      pkg
    end
  end

  def call(action)
    unless [ :list_deps, :clean ].include? action
      # check dependencies before doing anything else
      unless (dep_spec = @src_pkg.missing_build_dependencies).empty?
        raise StandardError, "missing build dependencies: #{dep_spec}"
      end
    end

    self.send(action)
  end

  def list_deps()
    puts @src_pkg.build_dependencies.to_s
  end

  def prepare()
    ['SOURCE', 'BUILD'].each do |s|
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
    source_dir  = @defines['XPACK_SOURCE_DIR']
    build_dir   = @defines['XPACK_BUILD_DIR']
    install_dir = @defines['XPACK_INSTALL_DIR']
    if File.exist?(install_dir) and \
      install_dir != source_dir and \
      install_dir != build_dir
        FileUtils.remove_entry_secure(install_dir)
    end
    File.exist?(install_dir) or Dir.mkdir install_dir
    @src_pkg.install @defines
  end

  def package()
    shlib_cache = ShlibCache.new()
    @bin_pkgs.each do |pkg|
      pkg.prepare
      shlib_cache.overlay_package(pkg)
    end
    @bin_pkgs.each do |pkg|
      pkg.pack(shlib_cache)
    end
  end

  def repackage()
    install
    package
  end

  def clean()
    @src_pkg.clean @defines
  end

  def default()
    prepare
    build
    install
    package
  end

end

