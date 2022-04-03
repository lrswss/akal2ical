#!/usr/bin/perl -w
############################################################################
#
# akal2ical v0.3.1 (03.04.2022)
# Copyright (c) 2018-2022 Lars Wessels <software@bytebox.org>
#
# Aus dem Abfuhrkalender des AfA Karlsruhe die Termine zu der angegebenen
# Adresse - die leider nur als HTML-Tabelle angezeigt werden - auslesen
# und in einer iCal-Datei speichern. Da auf den Webseiten des AfA nur die
# Abfuhrtermine der kommenden drei Wochen angezeigt werden, muss dieses
# Skript regelmäßig (bspw. wöchentlich per cron) aufgerufen werden.
#
# Diese Skript gehört NICHT zum offiziellen Informationsangebot des AfA
# Karlsruhe, sondern nutzt lediglich die über die öffentlichen Webseiten des
# AfA zur Verfügung gestellten Informationen. Alle Angaben sind ohne Gewähr!
#
# Siehe auch: https://web6.karlsruhe.de/service/abfall/akal/akal.php
#
############################################################################
#
# Dieses Skript benötigt folgende Debian-Pakete (apt-get install <name>):
# - libwww-perl
# - libhtml-strip-perl 
# - libdata-ical-perl
# - libdatetime-format-ical-perl
# - libdigest-md5-perl
# - libmojolicious-perl 
#
############################################################################
#
# Copyright (c) 2018-2022 Lars Wessels <software@bytebox.org>
#
# Dieses Programm ist freie Software. Sie können es unter den Bedingungen
# der GNU General Public License, wie von der Free Software Foundation
# veröffentlicht, weitergeben und/oder modifizieren, entweder gemäß
# Version 3 der Lizenz oder (nach Ihrer Option) jeder späteren Version.
#
# Die Veröffentlichung dieses Programms erfolgt in der Hoffnung, dass es
# Ihnen von Nutzen sein wird, aber OHNE IRGENDEINE GARANTIE, sogar ohne
# die implizite Garantie der MARKTREIFE oder der VERWENDBARKEIT FÜR EINEN
# BESTIMMTEN ZWECK. Details finden Sie in der GNU General Public License.
#
# Sie sollten ein Exemplar der GNU General Public License zusammen mit diesem
# Programm erhalten haben. Falls nicht, siehe <http://www.gnu.org/licenses/>. 
#
############################################################################

use LWP::Simple;
use HTML::Strip;
use Data::ICal;
use Data::ICal::Entry::Event;
use Data::ICal::Entry::Alarm::Display;
use DateTime::Format::ICal;
use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use Mojo::DOM;
use Getopt::Long;
use vars qw($street $street_num $test);
use strict;

############################################################################

# URL zum AfA-Abfallkalender-Skript
my $base_url = 'https://web6.karlsruhe.de/service/abfall/akal/akal.php';

# Termine für diese Tonnen bzw. Müllkategorien auslesen
# mögliche Werte: schwarz od. Restmüll, grün od. Bioabfall,
# rot od. Wertstoff, blau od. Altpapier
my @bins = ('schwarz', 'grün', 'blau', 'rot');
my $bins = '';  # bei Angabe auf Kommandozeile

# Startzeit (Stunde) für Abfuhrtermine
my $dtstart_hour = 6;

# Dauer (Minuten) des Abfuhrtermins im Kalender 
my $event_duration = 15;

# Minuten vorher erinnern (0 = keine Erinnerung)
my $alarm_min = 0;  

# Pfad und Name der iCal-Ausgabedatei (*.ics)
my $ical_file = '';

############################################################################

# Versionsnummer
my $p_version = 'v0.3.1';

# Kommandozeilenoptionen definieren
my $help = 0;
GetOptions('strasse=s' => \$street, 'nummer=s' => \$street_num,
	'startzeit=i' => \$dtstart_hour, 'erinnerung=i' => \$alarm_min,
	'dauer=i' => \$event_duration, 'datei=s' => \$ical_file,
	'tonnen=s' => \$bins, 'test' => \$test, 'hilfe' => \$help) or &usage();

# Straßenname und (seit Aug. 2021) Hausnummer müssen angegeben werden...
&usage() if (!$street || !$street_num || $help);

# optionale Eingabewerte überprüfen
$dtstart_hour = int($dtstart_hour);
if ($dtstart_hour < 0 || $dtstart_hour > 23) {
	print STDERR "FEHLER: Die Startzeit für die Abfuhrtermine muss zwischen 0 und 23 liegen!\n\n";
	exit(5);
}
$alarm_min = int($alarm_min);
if ($alarm_min < 0 || $alarm_min > 1440 ) {
	print STDERR "FEHLER: Die Vorwarnzeit für die Abfuhrtermine muss zwischen 0 und 1440 Minuten liegen!\n";
	exit(5);
}
$event_duration = int($event_duration);
if ($event_duration < 10 || $event_duration > 180 ) {
	print STDERR "FEHLER: Die Dauer der Abfuhrtermine muss zwischen 0 und 180 Minuten liegen!\n";
	exit(5);
}

if ($ical_file =~ /^-/) {
	print STDERR "FEHLER: Ungültiger Dateiname für ICS-Datei!\n";
	exit(5);
}

# Nur nach Terminen für bestimmte Abfahltonnen suchen
my $_bins = $bins;
if (length($bins) >= 3) {
	$_bins =~ s/(rot|grün|blau|schwarz|,)//g;
	if ($bins =~ /(rot|grün|blau|schwarz)/i && !$_bins) {
		@bins = ();
		if ($bins !~ /,/) {
			push(@bins, $bins);
		} else {
			@bins = split(',', $bins);
		}
	} else {
		print STDERR "FEHLER: Gültige Werte für --tonnen sind schwarz, grün, rot oder blau!\n";
		exit(5);
	}
}

# Den angegebenen Straßennamen(teil) in Großbuchstaben
# umwandeln und passende Straßennamen online beim AfA suchen
my @street = split(/ /, $street); $street = '';
while (my $part = shift(@street)) {
	$street .= uc($part); # Straßennamen groß schreiben
	$street =~ tr/äöü/ÄÖÜ/;
	$street =~ s/STRASSE/STRAßE/;
	$street .= " " if ($#street > -1);
}
my $street = &query_streets($street);  # Rückgabe bei gültigem Straßenamen

# Nun die Abfuhrtermine für die gefundene Adresse abrufen
$street_num =~ s/ //g;
print STDERR "Sende Anfrage '".$base_url."?strasse=".$street."&hausnr=".$street_num."'...\n";
my $content = get($base_url.'?strasse='.$street.'&hausnr='.$street_num);

# HTML-Tags löschen
my $stripper = HTML::Strip->new();
my $text = $stripper->parse($content);
$text =~ s/[\n\r]//g;
$stripper->eof;

# Extrahierten Text in Tokens aufteilen und nach
# Schlüsselwörtern für Abfuhrtermine durchsuchen
my %pos;
my @tokens = split(/ /, $text);
foreach (0..$#tokens) {
	if ($tokens[$_] =~ /Restm/ && !$pos{'Restmüll'}) { $pos{'Restmüll'} = $_; }
	if ($tokens[$_] =~ /Bioabfall/ && !$pos{'Bioabfall'}) { $pos{'Bioabfall'} = $_; }
	if ($tokens[$_] =~ /Wertstoff/ && !$pos{'Wertstoff'}) { $pos{'Wertstoff'} = $_; }
	if ($tokens[$_] =~ /Papier/) { $pos{'Papier'} = $_; }
	if ($tokens[$_] =~ /Haushaltsgro/) { $pos{'Grossgeraete'} = $_; }
	if ($tokens[$_] =~ /ensperrm/ && !$pos{'Sperrmuell'}) { $pos{'Sperrmuell'} = $_; }
}

# neuen Kalender im iCalendar-Format erzeugen
my $calendar = Data::ICal->new();
my $count = 0;
my $i_max;

# Abfuhrtermine Restmüll in Text-Tokens suchen
my @black_bin;
if ((grep { $_ =~ m/Restmüll|schwarz/ } @bins) && $pos{'Restmüll'}) {
	if ($pos{'Bioabfall'}) {
		$i_max = $pos{'Bioabfall'};
	} elsif ($pos{'Wertstoff'}) {
		$i_max = $pos{'Wertstoff'};
	} elsif ($pos{'Papier'}) {
		$i_max = $pos{'Papier'};
	} else {
		$i_max = $pos{'Grossgeraete'};
	}
	for (my $i = $pos{'Restmüll'}; $i < $i_max; $i++) {
		if ($tokens[$i-1] =~ /den/ && $tokens[$i] =~ /(\d\d)\.(\d\d)\.(\d{4})/ && !(grep { $_ eq $tokens[$i] } @black_bin)) {
			push(@black_bin, $tokens[$i]);
			$calendar->add_entry(&create_event($street, 'Restmülltonne', $3, $2, $1));
			$count++;
		}
	}
	push(@black_bin, 'Keine Abfuhrtermine gefunden') if ($#black_bin < 0);
}

# Abfuhrtermine Biomüll in Text-Tokens suchen
my @green_bin;
if ((grep { $_ =~ /Biomüll|Bioabfall|grün/ } @bins) && $pos{'Bioabfall'}) {
	if ($pos{'Wertstoff'}) {
		$i_max = $pos{'Wertstoff'};
	} elsif ($pos{'Papier'}) {
		$i_max = $pos{'Papier'};
	} else {
		$i_max = $pos{'Grossgeraete'};
	}
	for (my $i = $pos{'Bioabfall'}; $i < $pos{'Wertstoff'}; $i++) {
		if ($tokens[$i-1] =~ /den/ && $tokens[$i] =~ /(\d\d)\.(\d\d)\.(\d{4})/ && !(grep { $_ eq $tokens[$i] } @green_bin)) {
			push(@green_bin, $tokens[$i]);
			$calendar->add_entry(&create_event($street, 'Bioabfall', $3, $2, $1));
			$count++;
		}
	}
	push(@green_bin, 'Keine Abfuhrtermine gefunden') if ($#green_bin < 0);
}

# Abfuhrtermine Wertstoff in Text-Tokens suchen
my @red_bin;
if ((grep { $_ =~ /Wertstoff|gelb|rot/ } @bins) && $pos{'Wertstoff'} && ($pos{'Papier'} || $pos{'Grossgeraete'})) {
	my $i_max = $pos{'Papier'} ? $pos{'Papier'} : $pos{'Grossgeraete'};
	for (my $i = $pos{'Wertstoff'}; $i < $i_max; $i++) {
		if ($tokens[$i-1] =~ /den/ && $tokens[$i] =~ /(\d\d)\.(\d\d)\.(\d{4})/ && !(grep { $_ eq $tokens[$i] } @red_bin)) {
			push(@red_bin, $tokens[$i]);
			$calendar->add_entry(&create_event($street, 'Wertstofftonne', $3, $2, $1));
			$count++;
		}
	}
	push(@red_bin, 'Keine Abfuhrtermine gefunden.') if ($#red_bin < 0);
}

# Abfuhrtermine Altpapier in Text-Tokens suchen
my @blue_bin;
if ((grep { $_ =~ /apier|blau/ } @bins) && $pos{'Papier'} && $pos{'Grossgeraete'}) {
	for (my $i = $pos{'Papier'}; $i < $pos{'Sperrmuell'}; $i++) {
		if ($tokens[$i-1] =~ /den/ && $tokens[$i] =~ /(\d\d)\.(\d\d)\.(\d{4})/ && !(grep { $_ eq $tokens[$i] } @blue_bin)) {
			push(@blue_bin, $tokens[$i]);
			$calendar->add_entry(&create_event($street, 'Altpapier', $3, $2, $1));
			$count++;
		}
	}
	push(@blue_bin, 'Keine Abfuhrtermine gefunden.') if ($#blue_bin < 0);
}

# Sperrmülltermin in Text-Tokens suchen (einmal pro Jahr)
my @bulky;
if ($pos{'Sperrmuell'}) {
	for (my $i = $pos{'Sperrmuell'}; $i < $pos{'Sperrmuell'}+10; $i++) {
		if ($#bulky < 0 && $tokens[$i] =~ /(\d\d)\.(\d\d)\.(\d{4})/) {
			push(@bulky, $tokens[$i]);
			$calendar->add_entry(&create_event($street, 'Straßensperrmüll', $3, $2, $1));
			$count++;
		}
	}
}
push(@bulky, 'Keinen Straßensperrmülltermin gefunden.') if ($#bulky < 0);

if (!$count) {
	printf STDERR "Keine Abfuhrtermine für die Adresse '%s %s' beim AfA Karlsruhe gefunden!\n", $street, $street_num;
	exit(1);
} elsif ($test) {
	printf "Kommende Abfuhrtermine für '%s %s':\n", $street, $street_num;
	print "Restmüll (schwarze Tonne): ", join(' ', @black_bin),"\n" if ($#black_bin > -1);
	print "Bioabfall (grüne Tonne): ", join(' ', @green_bin),"\n" if ($#green_bin > -1);
	print "Wertstoff (rote Tonne): ", join(' ', @red_bin),"\n" if ($#red_bin > -1);
	print "Altpapier (blaue Tonne): ", join(' ', @blue_bin),"\n" if ($#blue_bin > -1);
	print "Straßensperrmüll: ", join(' ', @bulky),"\n" if ($#bulky > -1);
} else {
	# Warnung ausgeben, wenn nicht für alle Müllkategorien Abfuhrtermine gefunden wurden
	print STDERR "Keine Abfuhrtemine für Restmüll (schwarze Tonne) gefunden!\n" if ($#black_bin > -1 && $black_bin[0] =~ /Kein/);
	print STDERR "Keine Abfuhrtemine für Bioabfall (grüne Tonne) gefunden!\n" if ($#green_bin > -1 && $green_bin[0] =~ /Kein/);
	print STDERR "Keine Abfuhrtemine für Wertstoff (rote Tonne) gefunden!\n" if ($#red_bin > -1 && $red_bin[0] =~ /Kein/);
	print STDERR "Keine Abfuhrtemine für Altpapier (blaue Tonne) gefunden.\n" if ($#blue_bin > -1 && $blue_bin[0] =~ /Kein/);
	print STDERR "Keinen Straßenperrmülltermin gefunden.\n" if ($#bulky < 0);

	# Abfuhrtermine in iCal-Kalenderdatei *.ics speichern
	my %replace = (	"Ä" => "Ae", "Ü" => "Ue", "Ö" => "Oe", "ß" => "ss", " " => "_");
	$street =~ s/(Ä|Ü|Ö|ß|\s+)/$replace{$1}/g;
	$ical_file = lc($street).'.ics' if (!$ical_file);
	open(ICAL, ">$ical_file") or die "FEHLER: kann die Datei '$ical_file' nicht erstellen: $!\n";
	my $ical = $calendar->as_string;
	$ical =~ s?PRODID.+?PRODID:-//software\@bytebox.org//akal2ical $p_version//DE?;
	print ICAL $ical;
	close(ICAL);
	printf STDERR "Es wurden %d Abfuhrtemine in Datei '$ical_file' gespeichert.\n", $count;
}

exit(0);



# einen Kalendereintrag (event) für einen Abfuhrtermin erzeugen
sub create_event() {
	my ($street, $bin, $year, $month, $day) = @_;
	my $uid = md5_hex($bin.$year.$month.$day);
	my $vevent = Data::ICal::Entry::Event->new();
	$vevent->add_properties(
		uid => $uid,
		summary => $bin,
		description => "Abfuhrtermin $bin für $street",
		location => "$street, Karlsruhe",
		transp => "TRANSPARENT",
		class => "PUBLIC",
		url => $base_url,
		dtstamp => DateTime::Format::ICal->format_datetime(DateTime->now),
		dtstart => DateTime::Format::ICal->format_datetime(DateTime->new(
			day => $day, month => $month, year => $year,
			hour => $dtstart_hour, minute => 00)),
		dtend => DateTime::Format::ICal->format_datetime(DateTime->new(
			day => $day, month => $month, year => $year,	
			hour => $dtstart_hour, minute => $event_duration))
	);

	# ggf. Erinnerung an Abfuhrtermin erstellen
	if (int($alarm_min) > 0) {
		my $valarm = Data::ICal::Entry::Alarm::Display->new();
		$valarm->add_properties(
	    	description => $bin,
			trigger => '-PT'.$alarm_min.'M'
		);
		$vevent->add_entry($valarm);
	}

	return $vevent;
}


# alle bekannten Straßennamen beim AfA nach gegebener Zeichenkette durchsuchen
# Namen werden aus dem Code für die JavaScript-Autocomplete-Funktion ausgelesen
sub query_streets() {
	my $query = shift;

	printf STDERR "Nach dem Straßennamen '%s' beim AfA Karlsruhe suchen...\n", $query;
	my @afa_streets;
	foreach my $html (split(/\r\n/, get($base_url))) {
		if ($html =~ /strassenliste/) {
			$html =~ s/.*\[//;
			$html =~ s/'//g;
			$html =~ s/,\].*//;
			@afa_streets = split(/,/, encode_utf8($html));
		}
	}

	if ($#afa_streets < 0) {
		print STDERR "Fehler beim Auslesen der Straßennamen von AfA-Webseite.\n";
		exit(4);
	}

	my @streets;
	foreach my $street (@afa_streets) {
		if ($street =~ /^$query$/i) {
			return $street;
		} else {
			push(@streets, $street) if ($street =~ /^$query/i);
		}
	}

	if ($#streets > 0) {
		printf STDERR "Es wurden %d passende Straßenname gefunden. Bitte einen der ", $#streets+1;
		print STDERR "folgenden\nBezeichner zur Abfrage der Abfuhrtermine verwenden:\n";
		foreach my $street (@streets) {
			print STDERR "- '$street'\n";
		}
		exit(2);
	} elsif ($#streets < 0) {
		print STDERR "Keinen passenden Straßennamen zur Anfrage '$query' gefunden.\n";
		exit(3);
	}
	return $streets[0];
}


# Hilfe zum Aufruf des Skript ausgeben
sub usage() {
	select STDERR;
	printf "\nakal2ical %s - Copyright (c) 2018-2022 Lars Wessels <software\@bytebox.org>\n", $p_version;
	print "Abfuhrtermine des AfA Karlsruhe für die angegebene Adresse abrufen\n";
	print "und als iCal-Datei (*.ics) speichern. Alle Angaben sind ohne Gewähr!\n\n";
	print "Aufruf: akal2ical.pl --strasse '<strassenname oder -namensteil>' --nummer '<hausnummer>'\n";
	print "Optionen: --startzeit <stunde>   : Startzeit für Abfuhrtermine (Standard 6 Uhr)\n";
	print "          --dauer <minuten>      : Dauer der Abfuhrtermine (Standard 15 Min.)\n";
	print "          --erinnerung <minuten> : Minuten vorher erinnern (Standard aus)\n";
	print "          --datei <dateipfad>    : vollständiger Pfad zur iCal-Ausgabedatei (*.ics)\n";
	print "          --tonnen <kommaliste>  : Liste abzufragender Tonnen (schwarz,grün,rot,blau)\n";
	print "          --test                 : gefundene Abfuhrtermine nur anzeigen\n";
	print "          --hilfe                : diese Kurzhilfe anzeigen\n\n";
	print "Straßenname und Hausnummer jeweils in Hochkommata einschließen!\n";
	print "Beispiel: akal2ical.pl --strasse 'Weltzienstraße' --nummer '27'\n\n";
	print "Die Liste abzufragender Tonnen getrennt durch Komma und ohne Leerzeichen angeben.\n";
	print "Beispiel: akal2ical.pl --strasse 'Weltzienstraße' --nummer '27' --tonnen 'rot,grün,schwarz'\n\n";
	print "Dieses Programm wird unter der GNU General Public License v3 bereitsgestellt,\n";
	print "in der Hoffnung, dass es nützlich sein wird, aber OHNE JEDE GEWÄHRLEISTUNG;\n";
	print "sogar ohne die implizite Gewährleistung der MARKTFÄHIGKEIT oder EIGNUNG FÜR\n";
	print "EINEN BESTIMMTEN ZWECK. Weitere Details siehe https://www.gnu.org/licenses/\n\n";
	exit(4);
}
