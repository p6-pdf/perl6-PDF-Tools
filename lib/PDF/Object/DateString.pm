use v6;

use PDF::Object;

class PDF::Object::DateString
    is PDF::Object
    is DateTime {

=begin pod

see [PDF 1.7 Section 3.8.3 Dates ]

PDF defines a standard date format, which closely follows that of the international standard ASN.1 (Abstract Syntax Notation One), defined in ISO/IEC 8824. A date is an ASCII string of the form:
 C<(D:YYYYMMDDHHmmSSOHH'mm')>
 where:

=item  YYYY is the year
=item  MM is the month
=item  DD is the day (01–31)
=item  HH is the hour (00–23)
=item  mm is the minute (00–59)
=item  SS is the second (00–59)
=item  O is the relationship of local time to Universal Time (UT), denoted by one of the characters +, −, or Z (see below)
=item  HH followed by ' is the absolute value of the offset from UT in hours (00–23)
=item  mm followed by ' is the absolute value of the offset from UT in minutes (00–59)
=para
The apostrophe character (') after HH and mm is part of the syntax. All fields after the year are optional. (The prefix D : , although also optional, is strongly recommended.) The default values for MM and DD are both 01; all other
# numerical fields default to zero values. A plus sign (+) as the value of the O field signifies that local time is later than UT, a minus sign (−) signifies that local time is earlier than UT, and the letter Z signifies that local time is equal to UT. If no UT information is specified, the relationship of the specified time to UT is considered to be unknown. Regardless of whether the time zone is known, the rest of the date should be specified in local time.

=end pod

    use PDF::Object::Util :date-time-formatter;
    BEGIN our &formatter = &date-time-formatter;

    multi method new(Str $pdf-date!) {
	my \DateRx = rx/^ 'D:'? $<year>=\d**4 [$<month>=\d**2 [$<day>=\d**2 [$<hour>=\d**2 [$<min>=\d**2 [$<sec>=\d**2]? ]? ]? ]? ]?
			      [ $<tz-sign>=< + - Z > $<tz-hour>=\d**2 \' $<tz-min>=\d**2 \']? /;

	$pdf-date ~~ DateRx
	    or die "Date $pdf-date not in format: D:YYYYMMDDHHmmSS[+-Z]HH'mm'";

	my Str $iso-date = sprintf("%04d-%02d-%02dT%02d:%02d:%02d", $<year>, $<month>//1, $<day>//1, $<hour>//0, $<min>//0, $<sec>//0 )
	    ~ (!$<tz-sign> || $<tz-sign> eq 'Z'
	       ?? ''
	       !! sprintf '%s%02d%02d', $<tz-sign>//'+', $<tz-hour>//0, $<tz-min>//0 );

	nextwith( $iso-date, :&formatter );
    }

    multi method new(DateTime $dt!) {
        my %args = <year month day hour minute second timezone>.map({ $_ => $dt."$_"() });
        $.new( |%args, :&formatter);
    }

    multi method new(UInt :$year!, |c) {
        callwith( :&formatter, :$year, |c);
    }

    method content {
	my Str $literal = formatter( self );
	:$literal;
    }
}