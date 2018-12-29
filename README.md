# akal2ical v0.1 (29.12.2018)

Perl-Skript, um aus dem Abfuhrkalender des [AfA Karlsruhe](https://www.karlsruhe.de/b4/buergerdienste/abfall.de) 
die Termine zu einem angegebenen Straßenzug - die leider nur als HTML-Tabelle angezeigt 
werden - auszulesen und in einer iCal-Datei (\*.ics) zu speichern. Da auf den Webseiten des AfA
nur die Abfuhrtermine der kommenden drei Wochen anzeigt werden, muss dieses Skript regelmäßig
(bspw. wöchentlich per cron) aufgerufen werden.

Diese Skript gehört NICHT zum offiziellen Informationsangebot des AfA Karlsruhe, sondern nutzt
lediglich die über die öffentlichen Webseiten des AfA zur Verfügung gestellten Informationen. 
Alle Angaben sind ohne Gewähr!

Siehe auch: https://web3.karlsruhe.de/service/abfall/akal/akal.php

## Installation

Dieses Perl-Skript benötigt folgende Debian-Pakete (apt-get install \<paketname\>):
- libwww-perl
- libhtml-strip-perl
- libdata-ical-perl
- libdatetime-format-ical-perl
- libdigest-md5-perl
- libmojolicious-perl
  
## Lizenzbedingungen

Copyright (c) 2018  Lars Wessels (software@bytebox.org)

Dieses Programm ist freie Software. Sie können es unter den Bedingungen
der GNU General Public License, wie von der Free Software Foundation
veröffentlicht, weitergeben und/oder modifizieren, entweder gemäß
Version 3 der Lizenz oder (nach Ihrer Option) jeder späteren Version.

Die Veröffentlichung dieses Programms erfolgt in der Hoffnung, dass es
Ihnen von Nutzen sein wird, aber OHNE IRGENDEINE GARANTIE, sogar ohne
die implizite Garantie der MARKTREIFE oder der VERWENDBARKEIT FÜR EINEN
BESTIMMTEN ZWECK. Details finden Sie in der GNU General Public License.

Sie sollten ein Exemplar der GNU General Public License zusammen mit diesem
Programm erhalten haben. Falls nicht, siehe <http://www.gnu.org/licenses/>.
