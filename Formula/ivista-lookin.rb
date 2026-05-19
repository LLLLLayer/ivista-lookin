class IvistaLookin < Formula
  desc "Command-line interface for inspecting iOS apps with Lookin"
  homepage "https://github.com/LLLLLayer/ivista-lookin"
  url "https://github.com/LLLLLayer/ivista-lookin/releases/download/v0.1.3/ivista-lookin-macos-universal.zip"
  sha256 "c79c527cd7ea376f6d9b94ac619d7f8bcb29fca94d5825fd2001f007c52b9f46"
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
