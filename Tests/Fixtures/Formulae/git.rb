class Git < Formula
  desc "Distributed revision control system"
  homepage "https://git-scm.com"
  url "https://github.com/git/git/archive/v2.42.0.tar.gz"
  sha256 "c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0"
  
  depends_on "pkg-config" => :build
  depends_on "openssl@3"
  depends_on "curl"
  
  bottle do
    sha256 arm64_sonoma: "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1"
    sha256 arm64_ventura: "e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2"
    sha256 arm64_monterey: "f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3"
  end
end
