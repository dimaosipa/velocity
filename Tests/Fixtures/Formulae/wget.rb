class Wget < Formula
  desc "Internet file retriever"
  homepage "https://www.gnu.org/software/wget/"
  url "https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz"
  sha256 "766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"
  
  depends_on "pkg-config" => :build
  depends_on "openssl@3"
  
  bottle do
    sha256 arm64_sonoma: "4d180cd4ead91a34e2c2672189fc366b87ae86e6caa3acbf4845b272f57c859a"
    sha256 arm64_ventura: "7fce09705a52a2aff61c4bdd81b9d2a1a110539718ded2ad45562254ef0f5c22"
    sha256 arm64_monterey: "498cea03c8c9f5ab7b90a0c333122415f0360c09f837cafae6d8685d6846ced2"
  end
end
