package Apache::Scriptor;
$VERSION="1.20";
use CGI::WebOut;
use Cwd;

# constructor new()
# ������� ����� Apache::Scriptor-������.
sub new
{ my ($class)=@_;
  my $this = {
    Handlers        => {},
    HandDir         => ".",
    htaccess        => ".htaccess",
    # ����������, ����� ������ � ���������������� ��� ��������, �����
    # ����� ������ ��� � htaccess-��.
    self_scriptname => $ENV{SCRIPT_NAME}
  };
  return bless($this,$class);
}


# void set_handlers_dir(string $dir)
# ������������� ���������� ��� ������ ������������.
sub set_handlers_dir
{ my ($this,$dir)=@_;
  $this->{HandDir}=$dir;
}

# void addhandler(ext1=>[h1, h2,...], ext2=>[...])
# ������������� ����������(�) ��� ���������� ext1 � ext2.
# ����� h1, h2 � �.�. ������������ ����� ������ �� �������-�����������.
# ���� �� ��� ������ �� ��� ������, � ��� ������, �� � ������ ��������� 
# � ���������� ����������� ������������ ������� ��� ��������� �� �����,
# ��� �������� ��������� � ������ ����������� � ����������� ".pl" ��
# ����������, ������� ������ ������� set_handlers_dir().
sub addhandler
{ my ($this,%hands)=@_;
  %{$this->{Handlers}}=(%{$this->{Handlers}},%hands);
  return;
}

# void pushhandler(string ext, func &func)
# ��������� ���������� ��� ���������� ext � ����� ������ ������������.
sub pushhandler
{ my ($this,$ext,$func)=@_;
  $this->{Handlers}{$ext}||=[];
  push(@{$this->{Handlers}{$ext}},$func);
  return;
}

# void removehandler(ext1, ext2, ...)
# ������� ����������(�) ��� ���������� ext1 � ext2.
sub removehandler
{ my ($this,@ext)=@_;
  foreach (@ext) { delete $this->{Handlers}{$_} }
  return;
}

# void set_404_url($url)
# ������������� ����� �������� 404-� ������, �� ������� ����� ���������� 
# ��������, ���� ���� �� ������.
sub set_404_url
{ my ($th,$url)=@_;
  $th->{404}=$url;
}

# void set_htaccess_name($name)
# ������������� ��� htaccess-�����. �� ��������� ��� .htaccess.
sub set_htaccess_name
{ my ($th,$htaccess)=@_;
  $th->{htaccess}=$htaccess;
}

sub process_htaccess
{ my ($th,$fname)=@_;
  open(local *F,$fname) or return;
  # ������� �������� ��� ��������� �� .htaccess
  my %Action=();
  my @AddHandler=();
  while(!eof(F)) {
    my $s=<F>; $s=~s/^\s+|#.*|\s+$//sg; next if $s eq "";
    # ��������� Action
    if($s=~m/Action\s+([\w\d-]+)\s*"?([^"]+)"?/si) {
      $Action{$1}=1 if $2 eq $th->{self_scriptname};
    }
    # ��������� AddHandler
    if($s=~m/AddHandler\s+([\w\d-]+)\s*(.+)/si) {
      push @AddHandler, [ $1, [ map { s/^\s*\.?|\s+$//sg; $_?($_):() } split /\s+/, $2 ] ];
    }
    # ��������� ErrorDocument 404
    if($s=~/ErrorDocument\s+404\s+"?([^"]+)"?/si) {
      $th->set_404_url($1);
    }
  }
  # ����� ��������� ������� ������������
  my %ProcessedExt=();
  foreach my $info (@AddHandler) {
    my ($hand,$ext)=@$info;
    # ����� �������� �����������, ������� �� ��������� �� Apache::Scriptor.
    # �� �� ����� ����� ������� � ������� �����, ������� ��� ���������
    # Action � AddHandler ����� ���� �� �� �������.
    next if !$Action{$hand};
    # ��������� ��� ������� ���������� ���������� � �������
    foreach my $ext (@$ext) {
      # ���� ��� ���������� ����������� � ������� htaccess-����� 
      # �������, ��� ������, ��� ������ ��������� ������� ������������.
      # � ���� ������ ����� ������� ��� ��������� �������.
      if(!$ProcessedExt{$ext}) {
        $th->removehandler($ext);
        $ProcessedExt{$ext}=1;
      }
      # ����� �������� �������� pushhandler()
      $th->pushhandler($ext,$hand);
    }
  }
}

sub process_htaccesses
{ my ($th,$path)=@_;
  # ������� ���������� ��� ������ ���� � htaccess-������
  my @Hts=();
  while($path=~m{[/\\]}) {
    if(-d $path) {
      my $ht="$path/$th->{htaccess}";
      unshift(@Hts,$ht) if -f $ht;
    }
    $path=~s{[/\\][^/\\]*$}{}s;
  }
  # ����� ������������ ��� �����, ������� � ������ ���������
  map { $th->process_htaccess($_) } @Hts;
}

# void run_uri(string $uri [,string $path_translated])
# ��������� ��������� URI �� ���������. ���� ������ �������� $path_translated,
# �� �� �������� ������ ��� ����� � ���������� ��� ���������. � ��������� 
# ������ ��� ����� ����������� ������������� �� ������ $uri (��� �� ������
# �������� ��������� - ��������, ����� ����� �� �������, ���� ���������� ����
# �������� ��� Alias Apache).
sub run_uri
{ my ($this,$uri,$path)=@_;
  Header("X-Powered-by: Apache::Scriptor v$VERSION. (C) Dmitry Koterov <koterov at cpan dot org>") if !$CopySend++;

  # ������ �������� � ������ �������. ����� �������, ���������� ������
  # process_htaccesses � �.�. �� ��������� �� ����� ��������� �������
  # ����� ��������� �������.
  local $this->{Handlers}={%{$this->{Handlers}}};
  local $this->{404}=$this->{404};

  # ��������� �� URL � QUERY_STRING
  local ($ENV{SCRIPT_NAME},$q) = split /\?/, $uri, 2;
  $ENV{QUERY_STRING}=defined $q? $q : "";

  # ��������� ���� � ����� ������� �� URI
  if(!$path) {
    $path="$ENV{DOCUMENT_ROOT}$ENV{SCRIPT_NAME}";
  }

  # ������� ����� ���������� ���������, ����� ������ Apache::Scriptor;
  local $ENV{REQUEST_URI}     = $uri;
  local $ENV{SCRIPT_FILENAME} = $path;
  local $ENV{REDIRECT_URL};     delete($ENV{REDIRECT_URL});
  local $ENV{REDIRECT_STATUS};  delete($ENV{REDIRECT_STATUS});
  # ������ ������� ����������.
  my $MyDir=getcwd(); 
  ($MyDir) = $MyDir=~/(.*)/;
  my ($dir) = $path; $dir=~s{(.)[/\\][^/\\]*$}{$1}sg;
 
  chdir($dir); getcwd(); # getcwd: ���������� $ENV{PWD}. ��� ��� ����? ��� �����...
  # ������������ ����� .htaccess.
  $this->process_htaccesses($path);

  # ���. ������ ��������� ���������� ������� ����� ��, ��� � ��������,
  # ������� � ���������� ������� ����������. ��������� �����������.
  $this->__run_handlers();
  
  # ��������������� ������� ����������
  chdir($MyDir); getcwd(); 
}


# ���������� ������� - ��������� ����������� ��� �����, ������� ����� � %ENV.
# ���������� � ��������� ����� ����� (�� ����, %ENV ��������� � ����� �� ���������,
# ��� ����� �������� ������� ������� ������, � ������� ���������� �������������
# ���������� �� ���������).
sub __run_handlers
{ my ($th)=@_;
  # ���������� �����
  my ($ext)  = $ENV{SCRIPT_FILENAME}=~m|\.([^.]*)$|; if(!defined $ext) { $ext=""; }

  # �������� ������ ������������ ��� ����� ����������
  $th->{Handlers}{$ext} 
    or die "$ENV{SCRIPT_NAME}: could not find handlers chain for extension \"$ext\"\n";

  # ������� ����� (������� � ��� ���������� �����, ���� ��������)
  my $input="";
  if(open(local *F, $ENV{SCRIPT_FILENAME})) { local ($/,$\); binmode(F); $input=<F>; }

  # ���������� �� ���� ������������
  my $next=1; # ����� ���������� �����������
  my @hands=@{$th->{Handlers}{$ext}};
  NoAutoflush() if @hands>1;
  foreach my $hand (@hands)
  { # ������ ��������������� ������. ���� � ��� ����� ���� ����������, �� 
    # �������������� ����� �� �����������. ����� - �����������, ��� � ��������
    my $OutObj=$hands[$next++]? CGI::WebOut->new : undef;
    my $func=$hand; # ��������� �� �������
    # ��������� - ����� �� ��������� ����������?
    if((ref($func)||"") ne "CODE") {
      # ����������� �����
      package Apache::Scriptor::Handlers; 
      # ����������� ��� ��� � ���� ������?
      if(!*{$func}{CODE}) {
        my $hname="$th->{HandDir}/$func.pl";
        -f $hname or die "$ENV{SCRIPT_NAME}: could not load the file $hname for handler $hand\n";
        do "$hname";
        *{$func}{CODE} or die "$ENV{SCRIPT_NAME}: cannot find handler $hand in $hname after loading $hname\n";
      }
      # �������� ��������� �� ������� �����������
      local $this=$th;
      $func=*{$func}{CODE};
    }
    # ������� ����������� ��������� ��������: ������� �����.
    # �� ������ - ���������� ��� �, ��������� print, ����������� ���������.
    # � ������ ������ (���� �� ������) ������� ������ ���������� -1!
    my $result=&$func($input);
    if($result eq "-1") {
      if($th->{404} && $th->{404} ne $th->{self_scriptname}) {
        Redirect($th->{404});
        exit;
      } else {
        die "$hand: could not find the file $ENV{SCRIPT_FILENAME}\n";
      }
    }

    # ��, ��� ����������, ������ �� ������� ����� ��� ���������� �����������.
    # ���� ����� �� ���������������, �� ������ ���� "".
    $input=$OutObj?$OutObj->buf:"";
  }
  # ������������� ��������� �������� �� ������� ������ (��� ����� ������� ��� 
  # ���������� �����������, �������� ���). ���-�� �� � ������� � �������.
  print $input;
}



package Apache::Scriptor::Handlers;
use CGI::WebOut;
# � ���� ������ ������������� ����������� �����������, 
# �������, ������ �����, ����� ������������� � ������ �������.
# ������ � ���� ����� �������� �����������, ����������� �������������.

# ���������� �� ��������� - ������ ������� �����
sub default
{ my ($input,$fname)=@_;
  -f $ENV{SCRIPT_FILENAME} or return -1;
  CGI::WebOut::Header("Content-type: text/html");
  print $input;
}

# ���������� perl-��������. ���������������, ��� ����� ������� ���� ����� print.
sub perl
{ my ($input)=@_;
  -f $ENV{SCRIPT_FILENAME} or return -1;
  eval("\n#line 1 \"$ENV{SCRIPT_NAME}\"\npackage main; $input");
}

return 1;
__END__







=head1 NAME

Apache::Scriptor - Support for Apache handlers conveyor.

=head1 SYNOPSIS

Synopsis are not so easy as in other modules, that's why let's see example below.

=head1 FEATURES

=over 4

=item *

Uses ONLY perl binary.

=item *

Helps to organize the Apache handler conveyor. That means you can redirect the output from one handler to another handler.

=item *

Supports non-existance URL handling and 404 Error processing.

=item *

Uses C<.htaccess> files to configure.

=back


=head1 EXAMPLE

  ### Consider the server structure:
  ### /
  ###   _Kernel/
  ###      handlers/
  ###        s_copyright.pl
  ###        ...
  ###      .htaccess
  ###      Scriptor.pl
  ###   .htaccess
  ###   test.htm

  ### File /.htaccess:
    # Setting up the conveyor for .htm:
    # "input" => eperl => s_copyright => "output" 
    Action     perl "/_Kernel/Scriptor.pl"
    AddHandler perl .htm
    Action     s_copyright "/_Kernel/Scriptor.pl"
    AddHandler s_copyright .htm


  ### File /_Kernel/.htaccess:
    # Enables Scriptor.pl as perl executable
    Options ExecCGI
    AddHandler cgi-script .pl

  ### File /_Kernel/Scriptor.pl:
    #!/usr/local/bin/perl -w 
    use FindBin qw($Bin);          # ������� ����������
    my $HandDir="$Bin/handlers";   # ���������� � �������������
    # This is run not as CGI-script?
    if(!$ENV{DOCUMENT_ROOT} || !$ENV{SCRIPT_NAME} || !$ENV{SERVER_NAME}) {
      print "This script has to be used only as Apache handler!\n\n";
      exit;
    }
    # Non-Apache-handler run?
    if(!$ENV{REDIRECT_URL}) {
      print "Location: http"."://$ENV{SERVER_NAME}/\n\n";
      exit;
    }
    require Apache::Scriptor;
    my $Scr=Apache::Scriptor->new();
    # Setting up the handlers' directory.
    $Scr->set_handlers_dir($HandDir);
    # Go on!
    $Scr->run_uri($ENV{REQUEST_URI},$ENV{PATH_TRANSLATED});

  ### File /_Kernel/handlers/s_copyright.pl:
    sub s_copyright
    {  my ($input)=@_;
       -f $ENV{SCRIPT_FILENAME} or return -1; # Error indicator
       # Adds the comment string BEFORE all the output.
       print '<!-- Copyright (C) by Dmitry Koterov (koterov at cpan dot org) -->\n'.$input;
       return 0; # OK
    }

  ### File /test.htm:
    print "<html><body>Hello, world!</body></html>";

  ### Then, user enters the URL: http://ourhost.com/test.htm.
  ### The result will be:
    Content-type: text/html\n\n
    <!-- Copyright (C) by Dmitry Koterov (koterov at cpan dot org) -->\n
    Hello, world!

=head1 OVERVIEW

This module is used to handle all the requests through the Perl script 
(such as C</_Kernel/Scriptor.pl>, see above). This script is just calling
the handlers conveyor for the specified file types.

When you place directives like these in your C<.htaccess> file:

  Action     s_copyright "/_Kernel/Scriptor.pl"
  AddHandler s_copyright .htm

Apache sees that, to process C<.htm> document, C</_Kernel/Scriptor.pl> handler
should be used. Then, Apache::Scriptor starts, reads this C<.htaccess> and remembers
the handler name for C<.htm> document: it is C<s_copyright>. Apache::Scriptor searches 
for C</_Kernel/handlers/s_copyright.pl>, trying to find the subroutine with the same name:
C<s_copyright()>. Then it runs that and passes the document body, returned from the previous 
handler, as the first parameter. 

How to start the new conveyor for extension C<.html>, for example? It's easy: you
place some Action-AddHandler pairs into the C<.htaccess> file. You must choose
the name for these handlers corresponding to the Scriptor handler file names 
(placed in C</_Kernel/handlers>). Apache does NOT care about these names, but 
Apache::Scriptor does. See example above (it uses two handlers: built-in C<perl> and user-defined C<s_copyright>).

=head1 DESCRIPTION

=over 11

=item C<require Apache::Scriptor>

Loads the module core.

=item C<Apache::Scriptor'new>

Creates the new Apache::Scriptor object. Then you may set up its 
properties and run methods (see below).

=item C<$obj'set_handlers_dir($dir)>

Sets up the directory, which is used to search for handlers.

=item C<$obj'run_uri($uri [, $filename])>

Runs the specified URI through the handlers conveyer and prints out 
the result. If C<$filename> parameter is specified, module does not
try to convert URL to filename and uses it directly.

=item C<$obj'addhandler(ext1=>[h1, h2,...], ext2=>[...])>

Manually sets up the handlers' conveyor for document extensions. 
Values of C<h1>, C<h2> etc. could be code references or 
late-loadable function names (as while parsing the C<.htaccess> file).

=item C<$obj'pushhandler($ext, $handler)>

Adds the handler C<$handler> th the end of the conveyor for extension C<$ext>.

=item C<$obj'removehandler($ext)>

Removes all the handlers for extension C<$ext>.

=item C<$obj'set_404_url($url)>

Sets up the redirect address for 404 error. By default, this value is 
bringing up from C<.htaccess> files.

=item C<$obj'set_htaccess_name($name)>

Tells Apache::Scriptor object then Apache user configuration file is called C<$name>
(by default C<$name=".htaccess">).

=item C<$obj'process_htaccess($filename)>

Processes all the directives in the C<.htaccess> file C<$filename> and adds
all the found handlers th the object.

=item C<package Apache::Scriptor::Handlers>

This package holds ALL the handler subroutines. You can place 
some user-defined handlers into it before loading the module to 
avoid their late loading from handlers directory.

=back

=head1 AUTHOR

Dmitry Koterov <koterov at cpan dot org>, http://www.dklab.ru

=head1 SEE ALSO

C<CGI::WebOut>.

=cut
