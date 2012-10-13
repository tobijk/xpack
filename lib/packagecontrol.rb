# -*- encoding: utf-8 -*-
#
# This file is part of the XPack Package Generator
# Copyright (C) 2010-2011, Tobias Koch <tobias.koch@gmail.com>
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
require 'changelog'

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

    # copy source name to changelog
    xml_doc.at_xpath('/control/changelog')['source'] = source_name

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

    @changelog = Changelog.new(xml_doc.at_xpath('/control/changelog'))
  end

  def call(action)
    unless [ :list_deps, :clean ].include? action
      # check dependencies before doing anything else
      unless @parms[:ignore_deps]
        unless (dep_spec = @src_pkg.missing_build_dependencies).empty?
          raise StandardError, "missing build dependencies: #{dep_spec}"
        end
      end
    end

    self.send(action)
  end

  def list_deps()
    puts @src_pkg.build_dependencies.to_s
  end

  def unpack()
    directory = @defines["XPACK_SOURCE_DIR"]
    File.exist?(directory) or Dir.mkdir directory

    @src_pkg.unpack directory
    @src_pkg.patch  directory
  end

  def prepare()
    directory = @defines["XPACK_BUILD_DIR"]
    File.exist?(directory) or Dir.mkdir directory
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
    unpack
    prepare
    build
    install
    package
  end

  def debianize()
    debian_folder = @src_pkg.base_dir + '/debian'
    Dir.mkdir debian_folder unless File.exists? debian_folder

    # write debian/control
    File.open(debian_folder + '/control', 'w+', 0644) do |fp|
      fp.write(@src_pkg.meta_data)
      fp.write("\n")

      @bin_pkgs.each do |pkg|
        fp.write(pkg.meta_data('debianize'))
        fp.write("\n")
      end
    end

    # write maintainer scripts and install files
    @bin_pkgs.each do |pkg|
      pkg.maintainer_scripts.each do |script_name, content|
        File.open(debian_folder + "/#{pkg.name}.#{script_name}", 'w+', 0755) do |fp|
          fp.write content.rstrip + "\n"
        end
      end

      fp_dirs  = File.open(debian_folder + "/#{pkg.name}.dirs", 'w+', 0644)
      fp_files = File.open(debian_folder + "/#{pkg.name}.install", 'w+', 0644)

      pkg.content_spec.each do |entry, attr|
        entry = '.' if entry.empty?
        if attr.type == 'dir'
          fp_dirs.write entry + "\n"
        else
          fp_files.write entry + "\n"
        end
      end

      fp_dirs.close
      fp_files.close
    end

    # write debian/changelog
    File.open(debian_folder + '/changelog', 'w+', 0644) do |fp|
      fp.write @changelog.format_for_debian
    end

    # write debian/compat
    File.open(debian_folder + '/compat', 'w+', 0644) do |fp|
      fp.write "7\n"
    end

    # write xpack rules to separate shell scripts
    rules_folder = debian_folder + '/rules.d'
    Dir.mkdir rules_folder unless File.exists? rules_folder

    ['prepare', 'build', 'install', 'clean'].each do |action|
      File.open(rules_folder + "/#{action}.sh", 'w+', 0755) do |fp|
        fp.write("#!/bin/sh -ex\n\n")
        fp.write(@src_pkg.rules[action].to_s.strip)
        fp.write("\n\n")
      end
    end

    # write debian/rules
    File.open(debian_folder + '/rules', 'w+', 0755) do |fp|
      fp.write "#!/usr/bin/make -f\n\n"

      # write xpack environment variables
      xpack_base_dir = @defines['XPACK_BASE_DIR']
      fp.write "export XPACK_BASE_DIR := $(CURDIR)\n"
      ['SOURCE', 'BUILD', 'INSTALL'].each do |s|
        directory = @defines["XPACK_#{s}_DIR"].gsub(/^#{xpack_base_dir}\/*/, '')
        fp.write "export XPACK_#{s}_DIR := $(XPACK_BASE_DIR)/#{directory}\n"
      end
      fp.write "\n"

      fp.write "configure: configure-stamp\n"
      fp.write "configure-stamp:\n"
      fp.write "\tdh_testdir\n"
      fp.write "\tmkdir -p $(XPACK_SOURCE_DIR)\n"
      fp.write "\tmkdir -p $(XPACK_INSTALL_DIR)\n"
      fp.write "\tmkdir -p $(XPACK_BUILD_DIR)\n"
      @src_pkg.sources.each do |source, subdir|
        fp.write "\tmkdir -p $(XPACK_SOURCE_DIR)/#{subdir}\n" unless subdir.empty?
        fp.write "\ttar --directory $(XPACK_SOURCE_DIR)/#{subdir} \\\n"
        fp.write "\t    --strip-components=1 \\\n"
        fp.write "\t    -xvf #{source}\n"
      end
      @src_pkg.patches.each do |patch_file, subdir|
        patch_file = '$(XPACK_BASE_DIR)/' + patch_file \
          unless patch_file.start_with? '/'

        e_source_dir = \
          if subdir.empty?
            '$(XPACK_SOURCE_DIR)'
          else
            '$(XPACK_SOURCE_DIR)/' + subdir
          end

        fp.write "\tpatch -f -p1 -d #{e_source_dir} -i #{patch_file}\n"
      end
      fp.write "\t$(XPACK_BASE_DIR)/debian/rules.d/prepare.sh\n"
      fp.write "\ttouch configure-stamp\n\n"

      fp.write "build: build-stamp\n"
      fp.write "build-stamp: configure-stamp\n"
      fp.write "\tdh_testdir\n"
      fp.write "\t$(XPACK_BASE_DIR)/debian/rules.d/build.sh\n"
      fp.write "\ttouch build-stamp\n\n"

      fp.write "install: install-stamp\n"
      fp.write "install-stamp: build-stamp\n"
      fp.write "\tdh_testdir\n"
      fp.write "\t$(XPACK_BASE_DIR)/debian/rules.d/install.sh\n"
      fp.write "\tdh_installdirs\n"
      @bin_pkgs.each do |pkg|
        fp.write "\tdh_install --package=#{pkg.name} "
        if pkg.content_subdir
          fp.write "--sourcedir=$(XPACK_INSTALL_DIR)/#{pkg.content_subdir}/\n"
        else
          fp.write "--sourcedir=$(XPACK_INSTALL_DIR) \n"
        end
      end
      fp.write "\ttouch install-stamp\n\n"

      fp.write "binary: install-stamp\n"
      fp.write "\tdh_testdir\n"
      fp.write "\tdh_testroot\n"
      fp.write "\tdh_installchangelogs\n"
      fp.write "\tdh_installdocs\n"
      fp.write "\tdh_strip\n"
      fp.write "\tdh_compress\n"
      fp.write "\tdh_fixperms\n"
      fp.write "\tdh_makeshlibs\n"
      fp.write "\tdh_installdeb\n"
      fp.write "\tdh_shlibdeps\n"
      fp.write "\tdh_gencontrol\n"
      fp.write "\tdh_md5sums\n"
      fp.write "\tdh_builddeb\n\n"

      fp.write "clean:\n"
      fp.write "\tdh_testdir\n"
      fp.write "\t$(XPACK_BASE_DIR)/debian/rules.d/clean.sh\n"
      fp.write "\tdh_clean configure-stamp build-stamp install-stamp\n\n"

      fp.write ".PHONY: clean binary configure build install\n"
    end
  end

end

