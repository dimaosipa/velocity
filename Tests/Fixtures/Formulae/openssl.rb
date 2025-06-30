class Openssl < Formula
  desc "Cryptography and SSL/TLS Toolkit"
  homepage "https://www.openssl.org/"
  url "https://www.openssl.org/source/openssl-3.1.4.tar.gz"
  sha256 "166e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"
  
  depends_on "ca-certificates"
  
  bottle do
    sha256 arm64_sonoma: "e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2"
    sha256 arm64_ventura: "f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3"
    sha256 arm64_monterey: "a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4"
  end
end
