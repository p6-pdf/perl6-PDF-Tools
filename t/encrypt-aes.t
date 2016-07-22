use v6;
use Test;

use PDF::DAO::Type::PDF;
use PDF::Storage::Crypt;

# ensure consistant document ID generation
srand(123456);

my $pdf = PDF::DAO::Type::PDF.open: "t/helloworld.pdf";

my $user-pass = '';
my $owner-pass = 'ssh!';
my $expected-contents = 'BT /F1 24 Tf  100 250 Td (Hello, world!) Tj ET';
my $expected-author = 'PDF-Tools/t/dao-doc.t';

lives-ok { $pdf.encrypt( :$owner-pass, :$user-pass, :aes ); }, '$pdf.encrypt (AES) - lives';
is $pdf.crypt.is-owner, True, 'newly encrypted pdf - is-owner';
lives-ok {$pdf.save-as: "t/encrypt-aes.pdf";}, '$pdf.save-as - lives';
dies-ok { $pdf = PDF::DAO::Type::PDF.open: "t/encrypt-aes.pdf", :password<dunno> }, "open encrypted with incorrect password - dies";

lives-ok { $pdf = PDF::DAO::Type::PDF.open("t/encrypt-aes.pdf", :password($user-pass)) }, 'open with user password - lives';
is $pdf.crypt.is-owner, False, 'open with user password - not is-owner';
is $pdf<Info><Author>, $expected-author, 'open with user password - .Info.Author';
is $pdf<Root><Pages><Kids>[0]<Contents>.decoded, $expected-contents, 'open with user password - contents';

done-testing;
