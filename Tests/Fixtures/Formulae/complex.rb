class Complex < Formula
  desc "A complex formula with various features"
  homepage "https://complex.example.com"
  url "https://github.com/example/complex/archive/v2.5.1.tar.gz"
  sha256 "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
  version "2.5.1"
  license "MIT"
  
  bottle do
    rebuild 1
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "1111111111111111111111111111111111111111111111111111111111111111"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "2222222222222222222222222222222222222222222222222222222222222222"
    sha256 cellar: :any_skip_relocation, arm64_ventura: "3333333333333333333333333333333333333333333333333333333333333333"
    sha256 cellar: :any_skip_relocation, arm64_monterey: "4444444444444444444444444444444444444444444444444444444444444444"
    sha256 cellar: :any, x86_64_sonoma: "5555555555555555555555555555555555555555555555555555555555555555"
  end
  
  depends_on "cmake" => :build
  depends_on "rust" => :build
  depends_on "openssl@3"
  depends_on "zstd"
  depends_on :macos => :monterey
  
  def install
    system "cmake", "-S", ".", "-B", "build", *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end
  
  test do
    system "#{bin}/complex", "--version"
  end
end