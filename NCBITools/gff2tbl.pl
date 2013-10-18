#!/usr/bin/perl

=head1 DESCRIPTION

	gff2tbl.pl	-	Convert JGI's 'GFF3' data to NCBI's ridiculous 'tbl' format.

=head1 USAGE

	perl gff2tbl.pl -fasta scaffolds.fasta -gff jgi_annotated.gff -gene jgi_annotated.gene_product.txt -tbl output.tbl

=head2 Options

	-fasta	[characters]	Original assembled Fasta file
	-aka	[characters]	aliased file; from "toPhylipAndBack.pl" script
	-gff	[characters]	JGI's GFF file 
	-gene	[characters]	gene product file from JGI
	-tbl	[characters]	Output tbl file
	-min	[integers]	minimum sequence length

	-version -v	<BOOLEAN>	version of the current script
	-help	-h	<BOOLEAN>	This message. press q to exit this screen.	

=head1 Author

	Sunit Jain, (Thu Oct 10 12:48:37 EDT 2013)
	sunitj [AT] umich [DOT] edu

=cut

use strict;
use Getopt::Long;

my ($fasta, $gff, $gene_product);
my ($tbl, $fasta_out);
my $minLen=200;
my $minGeneLen= 300; # just used an arbitary number, to reduce the amount of manual curation required afterwords
my $aka;
my $help;
my $version="gff2tbl.pl\tv0.0.1b";
GetOptions(
	'f|fasta:s'=>\$fasta,
	'gff:s'=>\$gff,
	'gene:s'=>\$gene_product,
	'aka:s'=>\$aka,
	'tbl:s'=>\$tbl,
	'min:i'=>\$minLen,
	'o|out:s'=>\$fasta_out,
	'v|version'=>sub{print $version."\n"; exit;},
	'h|help'=>sub{system('perldoc', $0); exit;},
);
print "\# $version\n";

my %gene_prod; # gene_prod{locusID - same as one in %annotation}= product name
open(GP, "<".$gene_product); #|| die $!;
while(my $line=<GP>){
	chomp $line;
	next if $line=~ /^#/;
	next unless $line;

	my($locusID, $product)=split(/\t/, $line);
	$gene_prod{$locusID}=$product;
}
close GP;

my %alias;
open(ALIAS, "<".$aka);
while(my $line=<ALIAS>){
	chomp $line;
	next if $line=~ /^#/;
	next unless $line;

	my($alt, $orig)=split(/\t/, $line);
#	print OUT ">".$orig."\n".$fasta{$alt}."\n" if ($fasta{$alt});
	my($name, @desc)=split(/\s+/, $orig);
	$alias{$alt}=$name;
}
close ALIAS;

my %annotation;
open(GFF, "<".$gff)|| die $!;
while(my $line=<GFF>){
	chomp $line;
	next if $line=~ /^#/;
	next unless $line;

	&parseGFF3($line);
}
close GFF;

$/=">";
my %contigLen; # contig = length
open(FASTA, "<".$fasta) || die $!;
open(TBL, ">".$tbl) || die $!;
while(my $line=<FASTA>){
	chomp $line;
	next if $line=~ /^#/;
	next unless $line;
	
	my($header, @sequence)=split(/\n/, $line);
	my $seq=join("", @sequence);
	my ($name, @desc)=split(/\s+/, $header);
	my $parent;
	if($aka){
		$parent=$alias{$name};
	}
	else{
		$parent=$name;
	}
	
	&do_i_have_Ns($seq, $name);
	
	my $len=length($seq);
#	my $parent = $nSplit_mapped_contigs{$contig}{"Parent"};
	
	next if ($len < $minLen);
	print TBL ">Feature ".$name."\n"; #"\tLength:".$len."\n";
#	print ">Feature ".$name."\n"; #"\tLength:".$len."\n";
#	exit
	foreach my $locusID(keys %{$annotation{$parent}}){
		my $original_contig_gene_start=$annotation{$parent}{$locusID}{"START"};
		my $original_contig_gene_stop=$annotation{$parent}{$locusID}{"STOP"};
		($original_contig_gene_start, $original_contig_gene_stop)=sort{$a<=>$b} ($original_contig_gene_start, $original_contig_gene_stop);

		my ($incomplete, $gene_start, $gene_stop);
		# Question: Is the feature incomplete?
		
		# Workaround: Does the feature start at position 1 **AND** is less than "$minGeneLen" (300 by default). Assume it's incomplete.
		if (($original_contig_gene_start == 1) && (($original_contig_gene_stop - $original_contig_gene_stop) <= $minGeneLen)){ 
			$incomplete="\<";
		}
		# Workaround: Does the feature stop at the end of the scaffold **AND** is less than "$minGeneLen" (300 by default). Assume it's incomplete.
		if(($original_contig_gene_stop == $len) && (($original_contig_gene_stop - $original_contig_gene_stop) <= $minGeneLen)){
			$incomplete="\>";
		}

		if($annotation{$parent}{$locusID}{"STRAND"}=~ /^\-/){
			($gene_start, $gene_stop)=($original_contig_gene_stop, $original_contig_gene_start);
		}
		else{
			($gene_start, $gene_stop)=($original_contig_gene_start, $original_contig_gene_stop);
		}
	
		print TBL $incomplete;
		print TBL $gene_start."\t".$gene_stop."\t".$annotation{$parent}{$locusID}{"TYPE"}."\n"; #"\t".$annotation{$parent}{$locusID}{"LEN"}."\n";
		print TBL "\t\t\t";
		if($gene_prod{$locusID}){
			if($annotation{$parent}{$locusID}{"TYPE"}=~ /RNA/i){
				print TBL "product\t".$annotation{$parent}{$locusID}{"TYPE"}."-".$gene_prod{$locusID}."\n";
			}
			elsif($gene_prod{$locusID}=~ /hypothetical/i){
				print TBL "note\t".$gene_prod{$locusID}."\n";
			}
			else{
				print TBL "prot_desc\t".$gene_prod{$locusID}."\n";
			}
		}
		elsif($annotation{$parent}{$locusID}{"TYPE"}=~ /RNA/i){
			print TBL "product\t".$annotation{$parent}{$locusID}{"TYPE"}."\n";
		}
		else{
			my  ($ID, @desc)=split(/\_/, $locusID);
			my $type=join("_", @desc);
			print TBL "note\thypothetical protein\n";
			print TBL "note\tlocus=".$locusID."\t".$type."\n";
		}
	}	
}
close FASTA;
close TBL;
$/="\n";

sub find_Ns{
	my $seq=shift;
	my $header=shift;
	while($seq=~ /N{10,5000}/ig){
		print STDERR $header."\t".$-[0]."\t".$+[0]."\t".($+[0]-$-[0])."\n";
	}
}

sub parseGFF3{
#http://gmod.org/wiki/GFF
# contig, source, type, start,stop,score,strand, phase,attributes
    my $line=shift;
    my ($contig, $source, $type, $start,$stop,$score,$strand, $phase,$attribs)=split(/\t/, $line);
    
    my(@attributes)=split(/\;/, $attribs);

    my ($locusID, $ID, $Name,$Alias, $Parent, $Target, $Gap, $Derives_from, $Note, $Dbxref, $Onto, $repeat_type, $product);
    foreach my $att(@attributes){
		$locusID=$1 if ($att=~/locus_tag\=(.*)/);
		$ID= $1 if ($att=~/^ID\=(.*)/);
		$Name=$1 if ($att=~/^Name\=(.*)/);
		$Alias=$1 if ($att=~/^Alias\=(.*)/);
		$Parent=$1 if ($att=~/^Parent\=(.*)/);
		$Target=$1 if ($att=~/^Target\=(.*)/);
		$Gap=$1 if ($att=~/^Gap\=(.*)/);
		$Derives_from=$1 if ($att=~/^Derives_from\=(.*)/);
		$Note=$1 if ($att=~/^Note\=(.*)/);
		$Dbxref=$1 if ($att=~/Dbxref\=(.*)/);
		$Onto=$1 if ($att=~/^Ontology.*\=(.*)/);
		$repeat_type=$1 if ($att=~/^rpt_type\=(.*)/);
		$product=$1 if ($att=~/^product\=(.*)/);
    }
    if (! $locusID){
		foreach my $att(@attributes){
			if ($Parent){
				$locusID=$Parent."__exon"
			}
			elsif($type=~/repeat/){
				$locusID=$ID."__".$repeat_type; # rpt_type=CRISPR;rpt_unit=13023..13055
				$locusID.="[".$1."]" if ($att=~/rpt_unit\=(.*)/);
            }
            else{
				$locusID=$ID."__".$type;
            }
        }
    }
	$annotation{$contig}{$locusID}{"START"}=$start;
	$annotation{$contig}{$locusID}{"STOP"}=$stop;
	$annotation{$contig}{$locusID}{"TYPE"}=$type;
	$annotation{$contig}{$locusID}{"LEN"}=($stop-$start);
	$annotation{$contig}{$locusID}{"STRAND"}=$strand;
	$gene_prod{$locusID}=$product;
#        return $locusID;
}
