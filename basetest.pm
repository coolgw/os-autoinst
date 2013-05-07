package basetest;
use strict;
use bmwqemu;
use ocr;
use Time::HiRes;
use JSON;
use Data::Dumper;

sub new(;$) {
	my $class=shift;
	my $category = shift || 'unknown';
	my $self={class=>$class};
	$self->{lastscreenshot} = undef;
	$self->{details} = [];
	$self->{result} = undef;
	$self->{running} = 0;
	$self->{category} = $category;
	$self->{test_count} = 0;
	$self->{wav_fn} = undef;
	return bless $self, $class;
}

=head1 Methods

=head2 run

Body of the test to be implemented by child classes.
This code is run during test.

=head2 is_applicable

Return false if the test should be skipped.

Can eg. check ENV{BIGTEST}, ENV{LIVETEST}

=cut
sub is_applicable() {
	return 1;
}

sub record_screenmatch($$;$)
{
	my $self = shift;
	my $img = shift;
	my $needle = shift;
	my $tags = shift || [];

	my $count = ++$self->{"test_count"};
	my $testname = ref($self);

	my $result = {
		needle => $needle->{'needle'}->{'name'},
		area => $needle->{'area'},
		tags => [ @$tags ], # make a copy
		screenshot => sprintf("%s-%d.png", $testname, $count),
		result => 'ok',
	};
	
	my $fn = join('/', result_dir(), $result->{'screenshot'});
	$img->write($fn);

	$self->{result} ||= 'ok';
	
	push @{$self->{'details'}}, $result;
}

sub record_screenfail($@)
{
	my $self = shift;
	my %args = @_;
	my $img = $args{'img'};
	my $needles = $args{'needles'} || [];
	my $tags = $args{'tags'} || [];
	my $status = $args{'result'} || 'fail';
	my $overall = $args{'overall'}; # whether and how to set global test result

	my $count = ++$self->{"test_count"};
	my $testname = ref($self);

	my $candidates;
	my $diffcount = 0;
	for my $cand (@{$needles||[]}) {
		my $h = { 'name' => $cand->{'needle'}->{'name'}, 'area' => [] };
		for my $a (@{$cand->{'area'}}) {
			my $na = {};
			for my $i (qw/x y w h similarity result/) {
				$na->{$i} = $a->{$i};
			}
			my $imgname = sprintf("%s-%d-diff%d.png", $testname, $count, $diffcount++);
			$a->{'diff'}->write(join('/', result_dir(), $imgname));
			$na->{'diff'} = $imgname;
			push @{$h->{'area'}}, $na;
		}
		push @$candidates, $h;
	}

	my $result = {
		screenshot => sprintf("%s-%d.png", $testname, $count),
		result => $status,
	};

	$result->{'needles'} = $candidates if $candidates;
	$result->{'tags'} = [ @$tags ] if $tags; # make a copy
	
	my $fn = join('/', result_dir(), $result->{'screenshot'});
	$img->write($fn);

	$self->{result} ||= $overall if $overall;
	
	push @{$self->{'details'}}, $result;
}

sub details($)
{
	my $self = shift;
	return $self->{'details'};
}

sub result($;$)
{
	my $self = shift;
	$self->{result} = shift if @_;
	return $self->{result}||'na';
}

sub start()
{
	my $self = shift;
	$self->{running} = 1;
}

sub done()
{
	my $self = shift;
	$self->{running} = 0;
	$self->{result} ||= 'unk';
	unless ($self->{"test_count"}) {
		$self->take_screenshot();
	}
}

sub fail_if_running()
{
	my $self = shift;
	$self->{result} = 'fail' if $self->{'result'};
}

sub json()
{
	my $self = shift;
	return {
		'name' => ref $self,
		'details' => $self->details(),
		'result' => $self->result(),
		'category' => $self->{'category'},
	};
}

sub next_resultname($;$) {
	my $self = shift;
	my $type = shift;
	my $name = shift;
	my $path=result_dir;
	my $testname=ref($self);
	my $count=++$self->{"test_count"};
	if ($name) {
		return "$path/$testname-$count.$name.$type";
	} else {
		return "$path/$testname-$count.$type";
	}
}

=head2 take_screenshot

Can be called from C<run> to have screenshots in addition to the one taken via distri/opensuse/main.pm:installrunfunc after run finishes

=cut
sub take_screenshot(;$)
{
	my $self = shift;
	my $name = shift; # unused, for compat

	my $count = ++$self->{"test_count"};
	my $testname = ref($self);

	my $img = bmwqemu::do_take_screenshot();

	my $result = {
		screenshot => sprintf("%s-%d.png", $testname, $count),
		result => 'unk',
	};

	my $fn = join('/', result_dir(), $result->{'screenshot'});
	$img->write($fn);

	push @{$self->{'details'}}, $result;

	if ($name) {
		return "test-$testname-$name";
	} else {
		return "test-$testname-$count";
	}
}

=head2 check_screen
check needle with a tag that consists of current test name and
counter. Convenience function around checkneedle
=cut
sub check_screen(;$)
{
	my $self = shift;
	my $name = shift;
	my $testname = ref($self);
	my $tag;

	my $count = ++$self->{"test_count"};

	if ($name) {
		$tag = "test-$testname-$name";
	} else {
		$tag = "test-$testname-$count";
	}

	return bmwqemu::checkneedle($tag, 1)
}

sub start_audiocapture()
{
	my $self = shift;
	my $fn = $self->next_resultname("wav");
	die "audio capture already in progress. Stop it first!\n" if ($self->{'wav_fn'});
	# TODO: we only support one capture atm
	$self->{'wav_fn'} = $fn;
	bmwqemu::do_start_audiocapture($fn);
}

sub stop_audiocapture()
{
	my $self=shift;
	# XXX: if this function is supposed to support more than one
	# capture at a time the capture index has to be determined
	# from the recorded filename as the test doesn't know the
	# index. We can find out the index for the capture by asking
	# qemu "info capture"
	bmwqemu::do_stop_audiocapture(0);

	my $result = {
		audio => $self->{'wav_fn'},
		result => 'unk',
	};

	push @{$self->{'details'}}, $result;

	return $result;
}

=head2 check_DTMF
stop audio capture and compare DTMF decoded result with reference
=cut
sub check_DTMF($)
{
	my $self = shift;
	my $ref = shift;

	my $result = $self->stop_audiocapture();
	$result->{'reference_text'} = $ref;

	my $decoded_text = bmwqemu::decodewav($result->{'wav_fn'});
	if((uc $ref) eq $decoded_text) {
		$result->{'result'} = 'ok';
	} else {
		$result->{'result'} = 'fail';
	}
	$result->{'decoded_text'} = $decoded_text;

	$self->{result} ||= $result->{'result'};
}

=head2 ocr_checklist

Optical Character Recognition matching.

Return a listref containing hashrefs like this:

  {
    screenshot=>2,		# nr of screenshot for the test to OCR
    x=>104, y=>201,		# position
    xs=>380, ys=>150,		# size
    pattern=>"H ?ello",		# regex to match the OCR result

    result=>"OK"		# or "fail"
  }

=cut
sub ocr_checklist {
	return []
}

=head2 check() [protected]

After C<run> is done, evaluate the screen dumps according to checklists.

Return a string "STATUS DESCRIPTION"
where STATUS is one of: OK fail unknown not-autochecked

=cut
sub check(%) {
	die("FIXME");
	my $self=shift;
	my $path=result_dir;
	$path=~s/\.ogv.*//;
	if(!-e $path) {
		my $dir = `cd ../.. ; pwd ..`;
		chomp($dir);
		$path = "$dir/$path";
	}
	my $testname=ref($self);
	my @screenshots=<$path/$testname-*.png>;
	my @wavdumps=<$path/$testname-*.wav>;
	my $wav_checklist=$self->wav_checklist();
	my $ocr_checklist=$self->ocr_checklist();

	#if(!keys %$checklist && !@screenshots && (!@wavdumps || !keys %$wav_checklist) && !@$ocr_checklist) { return "not-autochecked" } #FIXME: return properly

	print "CHECK $testname ", @screenshots, "\n";
	# Screenshot Check
	my @screenshot_results = ();
	foreach my $screenimg (@screenshots) {
		my $img = tinycv::read($screenimg);

		my $tag = $screenimg;
		$tag=~s{.*/$testname-(\d+)\.png}{$testname-$1};
		# that much about guessing, now try to open the json
		if (-s "$screenimg.json") {
			open(J, "$screenimg.json");
			my $j = decode_json(<J>);
			$tag = $j->{tag};
		}

		my $needles = needle::tags($tag) || [];
		my $screenshot_result = {'refimg_result' => 'unk', 'ocr_result' => 'na'};

		# Reference Image Check
		if(!@{$needles}) {
			diag("No REF needles for $tag");
			#push(@testreturn, "na");
			$screenshot_result->{refimg_result} = 'na';
		} else {
			my $foundneedle = $img->search($needles);
			if($foundneedle) {
				$screenshot_result->{refimg_result} = 'ok';
				my $need = $foundneedle->{'needle'};
				$screenshot_result->{refimg} = {
					'id' => $need->{'name'},
					'match' => [$foundneedle->{'x'}, $foundneedle->{'y'}],
					'size' => [$foundneedle->{'w'}, $foundneedle->{'h'}]
				      };
			} else {
				# if there are refs and none of them match, then fail
				$screenshot_result->{refimg_result} = 'fail';
			}
		}

		# OCR Check
		if(@$ocr_checklist) {
			my $img = tinycv::read($screenimg);
			foreach my $entry (@$ocr_checklist) {
				my @ocrrect = ($entry->{x}, $entry->{y}, $entry->{xs}, $entry->{ys});
				my $ocr = ocr::get_ocr($img, "", \@ocrrect);
				open(OCRFILE, ">$path/$testname-$entry->{screenshot}.txt");
				print OCRFILE $ocr;
				close(OCRFILE);
				print STDERR "\nOCR OUT: $ocr\n";
				if($ocr=~m/$entry->{pattern}/) {
					my $result = $entry->{result};
					$screenshot_result->{ocr_result} = lc($result);
					last;
				}
				else {
					$screenshot_result->{ocr_result} = 'unk';
				}
			}
		}

		push(@screenshot_results, $screenshot_result);

	}

	# Audio Check
	my @wavreturn = ();
	foreach my $audiofile (@wavdumps) {
		my $aid = $audiofile;
		$aid=~s{.*/$testname-(\d+)\.wav}{$1};
		if(defined $wav_checklist->{$aid}) {
			my $decoded_text = bmwqemu::decodewav($audiofile);
			if((uc $wav_checklist->{$aid}) eq $decoded_text) {
				push(@wavreturn, "ok");
			}
			else {
				push(@wavreturn, "fail");
			}
		}
		else {
			push(@wavreturn, "na");
		}
	}

	my @refimg_results = map($_->{refimg_result}, @screenshot_results);
	my @ocr_results = map($_->{ocr_result}, @screenshot_results);
	my @returnval = (@refimg_results, @ocr_results, @wavreturn );

	my $module_result = 'na';

	if(grep/fail/,@returnval) { $module_result = 'fail' }
	elsif(grep/ok/,@returnval) { $module_result = 'ok' }
	elsif(grep/unk/,@returnval) { $module_result = 'unk' } # none of our known results matched

	my $return_result = {
		'name' => $testname,
		'result' => $module_result,
		'screenshots' => [@screenshot_results],
		'audiodumps' => [@wavreturn]
	};
	print STDERR '--- '.JSON::to_json($return_result)."\n";
	return $return_result;
}

1;

# Local Variables:
# tab-width: 8
# cperl-indent-level: 8
# End:
