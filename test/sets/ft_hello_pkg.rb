require 'rubygems'
require 'libarchive_rs'
require 'packagecontrol'
require 'test/unit'

class TS_ReadArchive < Test::Unit::TestCase

  PACKAGE_DIR='data/hello-world-pkg'
  SPEC_FILE="#{PACKAGE_DIR}/pack/package.xml"
  PACKAGE_FILE="../hello_0.1.0-1_i386.deb"
  XPACK_SOURCE_DIR="#{PACKAGE_DIR}/hello-src"
  XPACK_INSTALL_DIR="#{PACKAGE_DIR}/tmp-install"

  CONTROL=<<EOF
Package: hello
Version: [-.0-9]*
Source: hello-world
Maintainer: Tobias Koch <tobias.koch@gmail.com>
Section: misc
Architecture: .*
Depends: libc6 \\(>= .*\\)
Description: Hello World! in C
 This package contains the Hello World! program written in C.\\s*
EOF

  def teardown
    File.unlink PACKAGE_FILE if File.exist? PACKAGE_FILE
  end

  def test_build_basic_package
    pkg_ctrl = PackageControl.new(SPEC_FILE, {})
    pkg_ctrl.default()

    # test prepare target executed?
    assert File.exist?("#{XPACK_SOURCE_DIR}/prepare.stamp")

    # make sure building went ok
    assert File.exist?(PACKAGE_FILE)
    assert File.exist?("#{XPACK_SOURCE_DIR}/hello_world.c")
    assert File.exist?("#{XPACK_INSTALL_DIR}/usr/bin/hello")
    assert File.exist?("#{XPACK_INSTALL_DIR}/usr/lib/debug/usr/bin/hello")

    # check that archive has proper format and contents
    Archive.read_open_filename(PACKAGE_FILE) do |ar|
      entry = ar.next_header
      assert_equal "debian-binary", entry.pathname
      assert_equal "2.0\n", ar.read_data

      entry = ar.next_header
      assert_equal "control.tar.gz", entry.pathname
      check_control_file(ar.read_data)

      entry = ar.next_header
      assert_equal "data.tar.gz", entry.pathname
      check_data_file(ar.read_data)
    end

    # check that cleanup was done
    pkg_ctrl.clean()
    assert !File.exist?(XPACK_SOURCE_DIR)
    assert !File.exist?(XPACK_INSTALL_DIR)
  end

  private

  def check_control_file(data)
    Archive.read_open_memory(data) do |ar|
      entry = ar.next_header
      assert_equal "control", entry.pathname
      assert /#{CONTROL}/ =~ ar.read_data

      entry = ar.next_header
      assert_equal "md5sums", entry.pathname
      assert /[0-9abcdef]+  usr\/bin\/hello/ =~ ar.read_data
    end
  end

  def check_data_file(data)
    Archive.read_open_memory(data) do |ar|
      entry = ar.next_header
      assert_equal "./usr/bin/hello", entry.pathname
    end
  end

end
