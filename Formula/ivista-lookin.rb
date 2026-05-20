class IvistaLookin < Formula
  desc "Command-line interface for inspecting iOS apps with Lookin"
  homepage "https://github.com/LLLLLayer/ivista-lookin"
  url "https://github.com/LLLLLayer/ivista-lookin/releases/download/v0.1.4/ivista-lookin-macos-universal.zip"
  sha256 "1374be2194600588078bfddbeb831b03b794221ba12dc1ca91e5b1b4e2221ab9"
  license "GPL-3.0-only"

  depends_on :macos

  def install
    package_dir = if (buildpath/"ivista-lookin").exist?
      buildpath
    else
      buildpath.children.find { |path| path.directory? && (path/"ivista-lookin").exist? }
    end

    odie "ivista-lookin executable not found in package" if package_dir.nil?

    libexec.install package_dir.children
    bin.install_symlink libexec/"ivista-lookin" => "ivista-lookin"
  end

  test do
    assert_path_exists libexec/"Frameworks/LookinShared.framework"
    assert_path_exists libexec/"Frameworks/ReactiveObjC.framework"

    output = shell_output("#{bin}/ivista-lookin --version")
    assert_match "LookinCLI", output
  end
end
