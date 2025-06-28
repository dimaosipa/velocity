class Simple < Formula
  desc "A simple test formula"
  homepage "https://example.com/simple"
  url "https://example.com/downloads/simple-1.0.0.tar.gz"
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  
  bottle do
    sha256 arm64_sonoma: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    sha256 arm64_ventura: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
  end
  
  depends_on "dependency1"
  depends_on "dependency2"
  
  def install
    bin.install "simple"
  end
end