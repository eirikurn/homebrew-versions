require 'formula'

class Postgresql9 < Formula
  homepage 'http://www.postgresql.org/'
  url 'http://ftp.postgresql.org/pub/source/v9.0.12/postgresql-9.0.12.tar.bz2'
  sha1 '5762f165c65de6781e1b07275b174cee5b3be2fd'

  depends_on 'readline'
  depends_on 'libxml2' if MacOS.version == :leopard
  depends_on 'ossp-uuid' => :recommended

  option 'no-python', 'Build without Python support'
  option 'no-perl', 'Build without Perl support'
  option 'enable-dtrace', 'Build with DTrace support'

  # Fix uuid-ossp build issues: http://archives.postgresql.org/pgsql-general/2012-07/msg00654.php
  def patches
    DATA
  end

  def install
    ENV.libxml2 if MacOS.version >= :snow_leopard

    args = ["--disable-debug",
            "--prefix=#{prefix}",
            "--enable-thread-safety",
            "--with-bonjour",
            "--with-gssapi",
            "--with-krb5",
            "--with-openssl",
            "--with-libxml", "--with-libxslt"]

    args << "--with-ossp-uuid" unless build.without? 'ossp-uuid'
    args << "--with-python" unless build.include? 'no-python'
    args << "--with-perl" unless build.include? 'no-perl'
    args << "--enable-dtrace" if build.include? 'enable-dtrace'

    args << "--datadir=#{share}/#{name}"
    args << "--docdir=#{doc}"

    unless build.include? 'without-ossp-uuid'
      ENV.append 'CFLAGS', `uuid-config --cflags`.strip
      ENV.append 'LDFLAGS', `uuid-config --ldflags`.strip
      ENV.append 'LIBS', `uuid-config --libs`.strip
    end

    if MacOS.prefer_64_bit? and not build.include? 'no-python'
      args << "ARCHFLAGS='-arch x86_64'"
      check_python_arch
    end

    system "./configure", *args
    system "make install"
    system "make install-docs"

    contribs = Dir.glob("contrib/*").select{ |path| File.directory?(path) }
    contribs.delete('contrib/start-scripts')
    contribs.delete('contrib/uuid-ossp') if build.include? 'without-ossp-uuid'

    contribs.each do |dir|
      system "cd #{dir}; make install"
    end

    (prefix+'org.postgresql.postgres.plist').write startup_plist
    (prefix+'org.postgresql.postgres.plist').chmod 0644
  end

  def check_python_arch
    # On 64-bit systems, we need to look for a 32-bit Framework Python.
    # The configure script prefers this Python version, and if it doesn't
    # have 64-bit support then linking will fail.
    framework_python = Pathname.new "/Library/Frameworks/Python.framework/Versions/Current/Python"
    return unless framework_python.exist?
    unless (archs_for_command framework_python).include? :x86_64
      opoo "Detected a framework Python that does not have 64-bit support in:"
      puts <<-EOS.undent
          #{framework_python}

        The configure script seems to prefer this version of Python over any others,
        so you may experience linker problems as described in:
          http://osdir.com/ml/pgsql-general/2009-09/msg00160.html

        To fix this issue, you may need to either delete the version of Python
        shown above, or move it out of the way before brewing PostgreSQL.

        Note that a framework Python in /Library/Frameworks/Python.framework is
        the "MacPython" verison, and not the system-provided version which is in:
          /System/Library/Frameworks/Python.framework
      EOS
    end
  end

  def caveats
    s = <<-EOS
If builds of PostgreSQL 9 are failing and you have version 8.x installed,
you may need to remove the previous version first. See:
  https://github.com/mxcl/homebrew/issues/issue/2510

To build plpython against a specific Python, set PYTHON prior to brewing:
  PYTHON=/usr/local/bin/python  brew install postgresql
See:
  http://www.postgresql.org/docs/9.0/static/install-procedure.html


If this is your first install, create a database with:
  initdb #{var}/postgres9

If this is your first install, automatically load on login with:
  mkdir -p ~/Library/LaunchAgents
  cp #{prefix}/org.postgresql.postgres.plist ~/Library/LaunchAgents/
  launchctl load -w ~/Library/LaunchAgents/org.postgresql.postgres.plist

If this is an upgrade and you already have the org.postgresql.postgres.plist loaded:
  launchctl unload -w ~/Library/LaunchAgents/org.postgresql.postgres.plist
  cp #{prefix}/org.postgresql.postgres.plist ~/Library/LaunchAgents/
  launchctl load -w ~/Library/LaunchAgents/org.postgresql.postgres.plist

Or start manually with:
  pg_ctl -D #{var}/postgres9 -l #{var}/postgres9/server.log start

And stop with:
  pg_ctl -D #{var}/postgres9 stop -s -m fast


Some machines may require provisioning of shared memory:
  http://www.postgresql.org/docs/current/static/kernel-resources.html#SYSVIPC
EOS

    if MacOS.prefer_64_bit? then
      s << <<-EOS

If you want to install the postgres gem, including ARCHFLAGS is recommended:
    env ARCHFLAGS="-arch x86_64" gem install pg

To install gems without sudo, see the Homebrew wiki.
      EOS
    end

    return s
  end

  def startup_plist
    return <<-EOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>KeepAlive</key>
  <true/>
  <key>Label</key>
  <string>org.postgresql.postgres</string>
  <key>ProgramArguments</key>
  <array>
    <string>#{bin}/postgres</string>
    <string>-D</string>
    <string>#{var}/postgres9</string>
    <string>-r</string>
    <string>#{var}/postgres9/server.log</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>UserName</key>
  <string>#{`whoami`.chomp}</string>
  <key>WorkingDirectory</key>
  <string>#{HOMEBREW_PREFIX}</string>
  <key>StandardErrorPath</key>
  <string>#{var}/postgres9/server.log</string>
</dict>
</plist>
    EOPLIST
  end
end

__END__
diff --git a/contrib/uuid-ossp/uuid-ossp.c b/contrib/uuid-ossp/uuid-ossp.c
index d4fc62b..62b28ca 100644
--- a/contrib/uuid-ossp/uuid-ossp.c
+++ b/contrib/uuid-ossp/uuid-ossp.c
@@ -9,6 +9,7 @@
  *-------------------------------------------------------------------------
  */
 
+#define _XOPEN_SOURCE
 #include "postgres.h"
 #include "fmgr.h"
 #include "utils/builtins.h"
