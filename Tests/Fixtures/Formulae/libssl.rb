class Libssl < Formula
  desc "SSL/TLS cryptography library (legacy compatibility)"
  homepage "https://www.openssl.org/"
  url "https://www.openssl.org/source/openssl-1.1.1w.tar.gz"
  sha256 "b1c7d5e4f3a2b6c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5"
  
  bottle do
    sha256 arm64_sonoma: "c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4"
    sha256 arm64_ventura: "d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3"
    sha256 arm64_monterey: "e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2"
  end
end
