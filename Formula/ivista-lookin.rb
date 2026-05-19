class IvistaLookin < Formula
  desc "Command-line interface for inspecting iOS apps with Lookin"
  homepage "https://github.com/LLLLLayer/ivista-lookin"
  url "https://github.com/LLLLLayer/ivista-lookin/releases/download/v0.1.0/lookin-cli-macos-universal.zip"
  version "0.1.0"
  sha256 "26c1bfd64b66c093de97c2a9d3782b0bc8ac5b9601392b7e64ad1e613d0f0a89"
  license "GPL-3.0-only"

  depends_on :macos

  def install
    package_dir = if (buildpath/"lookin").exist?
      buildpath
    else
      buildpath.children.find { |path| path.directory? && (path/"lookin").exist? }
    end

    odie "lookin executable not found in package" if package_dir.nil?

    libexec.install package_dir.children
    bin.install_symlink libexec/"lookin" => "lookin"
  end

  test do
    assert_path_exists libexec/"Frameworks/LookinShared.framework"
    assert_path_exists libexec/"Frameworks/ReactiveObjC.framework"

    output = shell_output("#{bin}/lookin --version")
    assert_match "LookinCLI", output
  end
end
