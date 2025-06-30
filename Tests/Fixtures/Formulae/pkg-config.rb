class PkgConfig < Formula
  desc "Manage compile and link flags for libraries"
  homepage "https://www.freedesktop.org/wiki/Software/pkg-config/"
  url "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
  sha256 "266e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"
  
  bottle do
    sha256 arm64_sonoma: "f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3"
    sha256 arm64_ventura: "a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2"
    sha256 arm64_monterey: "b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1"
  end
end
