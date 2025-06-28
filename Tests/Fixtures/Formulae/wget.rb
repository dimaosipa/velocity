class Wget < Formula
  desc "Internet file retriever"
  homepage "https://www.gnu.org/software/wget/"
  url "https://ftp.gnu.org/gnu/wget/wget-1.21.3.tar.gz"
  sha256 "5726bb8bc5ca0f6dc7110f6416c4bb7019e2d2ff5bf93d1ca2ffcc6656f220e5"
  license "GPL-3.0-or-later"

  livecheck do
    url :homepage
    regex(/href=.*?wget[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_sonoma:   "982042e6b936ed0cf39f4b837fca156db8ed1bd0997bb88f90e1c6354a9b93f8"
    sha256 cellar: :any_skip_relocation, arm64_ventura:  "6f58b19368f5c2be9cfaa1bb936c60b543791d4b7b8f069bbf9880f645c97d5f"
    sha256 cellar: :any_skip_relocation, arm64_monterey: "dbb75782da307f505a8ef01e5a6e15c53cf1b40a85a71c8ef6d45e1529e7de8f"
    sha256 cellar: :any_skip_relocation, ventura:        "d2f28f2975ef5ca18a97e54f8fb0674a07bcc54c50e5dfda845a7f46af17e9d1"
    sha256 cellar: :any_skip_relocation, monterey:       "3ec3797ee7a9328af09b1ff8fabad1cdebbdadc946a0a7fc59e5a623c0e860f4"
    sha256 cellar: :any_skip_relocation, big_sur:        "faa3ec1b5b3c7797a0038cc9b2782b3a5a387e76a7bb8bb87bb4e7154e96de02"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "92a65e0643e0887e72a7c35dd470e7fc02090807b3cfa0e3ad2798df0f055fc8"
  end

  head do
    url "https://git.savannah.gnu.org/git/wget.git"

    depends_on "autoconf" => :build
    depends_on "automake" => :build
    depends_on "xz" => :build
    depends_on "gettext"
  end

  depends_on "pkg-config" => :build
  depends_on "openssl@3"

  on_linux do
    depends_on "libidn2"
  end

  def install
    system "./bootstrap", "--skip-po" if build.head?
    system "./configure", "--prefix=#{prefix}",
                          "--sysconfdir=#{etc}",
                          "--with-ssl=openssl",
                          "--with-libssl-prefix=#{Formula["openssl@3"].opt_prefix}",
                          "--disable-pcre",
                          "--disable-pcre2",
                          "--without-libpsl",
                          "--without-included-regex"
    system "make", "install"
  end

  test do
    system bin/"wget", "-O", "/dev/null", "https://google.com"
  end
end