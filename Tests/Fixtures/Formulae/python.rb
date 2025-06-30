class Python < Formula
  desc "Interpreted, interactive, object-oriented programming language"
  homepage "https://www.python.org/"
  url "https://www.python.org/ftp/python/3.12.0/Python-3.12.0.tar.xz"
  sha256 "c6e462c1b4c5e8c6b4c2a7b5d7e6e8a1b5c6d8e7a9b8c7d6e8f9a0b1c2d3e4f5"
  
  depends_on "pkg-config" => :build
  depends_on "openssl@3"
  depends_on "sqlite"
  
  bottle do
    sha256 arm64_sonoma: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
    sha256 arm64_ventura: "b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3"
    sha256 arm64_monterey: "c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4"
  end
end
