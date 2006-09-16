package Slim::Buttons::Input::Bar;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Input::Bar

=head1 SYNOPSIS

$params->{'valueRef'} = \$value;

Slim::Buttons::Common::pushMode($client, 'INPUT.Bar', $params);

=head1 DESCRIPTION

L<Slim::Buttons::Home> is a SlimServer module for creating and
navigating a configurable multilevel menu structure.

Avilable Parameters and their defaults:

 'header'          = ''    # message displayed on top line, can be a scalar, a code ref,
                           # or an array ref to a list of scalars or code refs
 'headerArgs'      = CV    # accepts C, and V, determines if the $client(C) and or the $valueRef(V) 
                          # are sent to the above codeRef
 'stringHeader'    = undef # if true, put the value of header through the string function
                           # before displaying it.
 'headerValue'     = undef
	set to 'scaled' to show the current value modified by the increment in parentheses
	set to 'unscaled' to show the current value in parentheses
	set to a codeRef which returns a string to be shown after the standard header
 'headerValueArgs' = CV    # accepts C, and V
 'headerValueUnit' = ''    # Set to a units symbol to be displayed before the closing paren
 'valueRef'        =       # reference to value to be selected
 'callback'        = undef # function to call to exit mode
 'overlayRef'      = undef # reference to subroutine to set any overlay display conditions.
 'overlayRefArgs'  = CV    # accepts C, and V
 'onChange'        = undef # code reference to execute when the valueRef is changed
 'onChangeArgs'    = CV    # accepts C, and V
 'min'             = 0     # minimum value for slider scale
 'max'             = 100   # maximum value for slider scale
 'mid'             = 0     # midpoint value for marking the division point for a balance bar.
 'midIsZero'       = 1     # set to 0 if you don't want the mid value to be interpreted as zero
 'increment'       = 2.5   # step value for each bar character or button press.
 'barOnDouble'     = 0     # set to 1 if the bar is preferred when using large text.
 'smoothing'       = 0     # set to 1 if you want the character display to use custom chars to 
                           # smooth the movement of the bar.

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Display::Display;
use Slim::Utils::Misc;

my %functions = ();

# XXXX - This should this be in init() - but we don't init Input methods
# before trying to use them.
Slim::Buttons::Common::addMode('INPUT.Bar', getFunctions(), \&setMode);

sub init {
	my $client = shift;

	if (!defined($client->modeParam('parentMode'))) {

		my $i = -2;

		while ($client->modeStack->[$i] =~ /^INPUT\./) {
			$i--;
		}

		$client->modeParam('parentMode', $client->modeStack->[$i]);
	}

	my %initValues = (
		'header'          => '',
		'min'             => 0,
		'mid'             => 0,
		'midIsZero'       => 1,
		'max'             => 100,
		'increment'       => 2.5,
		'barOnDouble'     => 0,
		'onChangeArgs'    => 'CV',
		'headerArgs'      => 'CV',
		'overlayRefArgs'  => 'CV',
		'headerValueArgs' => 'CV',
		'headerValueUnit' => '',

		# Bug: 2093 - Don't let the knob wrap or have acceleration when in INPUT.Bar mode.
		'knobFlags'       => Slim::Player::Client::KNOB_NOWRAP() | Slim::Player::Client::KNOB_NOACCELERATION(),
		'knobWidth'	  => 100,
		'knobHeight'	  => 1,
		'knobBackgroundForce' => 15,
	);

	# Set our defaults for this mode.
	for my $name (keys %initValues) {

		if (!defined $client->modeParam($name)) {

			$client->modeParam($name, $initValues{$name});
		}
	}
	
	my $min  = $client->modeParam('min');
	my $mid  = $client->modeParam('mid');
	my $max  = $client->modeParam('max');
	my $step = $client->modeParam('increment');

	my $listRef = [];
	my $j = 0;

	for (my $i = $min; $i <= $max; $i = $i + $step) {

		$listRef->[$j++] = $i;
	}

	$client->modeParam('listRef', $listRef);

	my $listIndex = $client->modeParam('listIndex');
	my $valueRef  = $client->modeParam('valueRef');

	if (!defined($listIndex)) {

		$listIndex = 0;

	} elsif ($listIndex > $#$listRef) {

		$listIndex = $#$listRef;
	}

	while ($listIndex < 0) {
		$listIndex += scalar(@$listRef);
	}

	if (!defined($valueRef)) {

		$$valueRef = $listRef->[$listIndex];
		$client->modeParam('valueRef', $valueRef);

	} elsif (!ref($valueRef)) {

		my $value = $valueRef;
		$valueRef = \$value;

		$client->modeParam('valueRef', $valueRef);
	}

	if ($$valueRef != $listRef->[$listIndex]) {

		my $newIndex;

		for ($newIndex = 0; $newIndex < scalar(@$listRef); $newIndex++) {

			last if $$valueRef <= $listRef->[$newIndex];
		}

		if ($newIndex < scalar(@$listRef)) {
			$listIndex = $newIndex;
		} else {
			$$valueRef = $listRef->[$listIndex];
		}
	}

	$client->modeParam('listIndex', $listIndex);

	my $headerValue = lc($client->modeParam('headerValue') || '');

	if ($headerValue eq 'scaled') {

		$client->modeParam('headerValue',\&scaledValue);

	} elsif ($headerValue eq 'unscaled') {

		$client->modeParam('headerValue',\&unscaledValue);
	}

	# change character at cursorPos (both up and down)
	%functions = (

		'up' => sub {
			my ($client, $funct, $functarg) = @_;

			changePos($client, 1, $funct);
		},

		'down' => sub {
			my ($client, $funct, $functarg) = @_;

			changePos($client, -1, $funct);
		},

		'knob' => sub {
			my ($client, $funct, $functarg) = @_;
			
			my $knobPos   = $client->knobPos();
			my $listIndex = $client->modeParam('listIndex');
			
			$::d_ui && msg("got a knob event for the bar: knobpos: $knobPos listindex: $listIndex\n");

			changePos($client, $knobPos - $listIndex, $funct);

			$::d_ui && msgf("new listindex: %d\n", $client->modeParam('listIndex'));
		},

		# call callback procedure
		'exit' => sub {
			my ($client, $funct, $functarg) = @_;

			if (!$functarg) {
				$functarg = 'exit'
			}

			exitInput($client, $functarg);
		},

		'passback' => sub {
			my ($client, $funct, $functarg) = @_;

			my $parentMode = $client->modeParam('parentMode');

			if (defined $parentMode) {
				Slim::Hardware::IR::executeButton($client, $client->lastirbutton, $client->lastirtime, $parentMode);
			}
		},
	);

	return 1;
}

sub scaledValue {
	my $client = shift;
	my $value  = shift;

	if ($client->modeParam('midIsZero')) {
		$value -= $client->modeParam('mid');
	}

	my $increment = $client->modeParam('increment');

	$value /= $increment if $increment;
	$value = int($value + 0.5);

	my $unit = $client->modeParam('headerValueUnit');

	if (!defined $unit) {
		$unit = '';
	}

	return " ($value$unit)"	
}

sub unscaledValue {
	my $client = shift;
	my $value  = shift;

	if ($client->modeParam('midIsZero')) {
		$value -= $client->modeParam('mid');
	}

	$value = int($value + 0.5);

	my $unit = $client->modeParam('headerValueUnit');

	if (!defined $unit) {
		$unit = '';
	}
	
	return " ($value$unit)"	
}

sub changePos {
	my ($client, $dir, $funct) = @_;

	my $listRef   = $client->modeParam('listRef');
	my $listIndex = $client->modeParam('listIndex');

	if (($listIndex == 0 && $dir < 0) || ($listIndex == (scalar(@$listRef) - 1) && $dir > 0)) {

		# not wrapping and at end of list
		return;
	}
	
	my $accel = 8; # Hz/sec
	my $rate  = 50; # Hz
	my $mid   = $client->modeParam('mid')||0;
	my $min   = $client->modeParam('min')||0;
	my $max   = $client->modeParam('max')||100;

	my $midpoint = ($mid-$min)/($max-$min)*(scalar(@$listRef) - 1);

	if (Slim::Hardware::IR::holdTime($client) > 0) {

		$dir *= Slim::Hardware::IR::repeatCount($client, $rate, $accel);
	}

	my $currVal     = $listIndex;
	my $newposition = $listIndex + $dir;

	if ($dir > 0) {

		if ($currVal < ($midpoint - .5) && ($currVal + $dir) >= ($midpoint - .5)) {

			# make the midpoint sticky by resetting the start of the hold
			$newposition = $midpoint;
			Slim::Hardware::IR::resetHoldStart($client);
		}

	} else {

		if ($currVal > ($midpoint + .5) && ($currVal + $dir) <= ($midpoint + .5)) {

			# make the midpoint sticky by resetting the start of the hold
			$newposition = $midpoint;
			Slim::Hardware::IR::resetHoldStart($client);
		}
	}

	$newposition = scalar(@$listRef) -1 if $newposition > scalar(@$listRef) -1;
	$newposition = 0 if $newposition < 0;

	my $valueRef = $client->modeParam('valueRef');
	$$valueRef   = $listRef->[$newposition];

	$client->modeParam('listIndex', int($newposition));

	my $onChange = $client->modeParam('onChange');

	if (ref($onChange) eq 'CODE') {

		my $onChangeArgs = $client->modeParam('onChangeArgs');
		my @args = ();

		push @args, $client if $onChangeArgs =~ /c/i;
		push @args, $$valueRef if $onChangeArgs =~ /v/i;

		$onChange->(@args);
	}

	$client->update;
}

sub lines {
	my $client = shift;

	# These parameters are used when calling this function from Slim::Display::Display
	my $value  = shift;
	my $header = shift;
	my $args   = shift;

	my $min = $args->{'min'};
	my $mid = $args->{'mid'};
	my $max = $args->{'max'};
	my $noOverlay = $args->{'noOverlay'} || 0;

	my ($line1, $line2);

	my $valueRef = $client->modeParam('valueRef');

	if (defined $value) {
		$valueRef = \$value;
	}

	my $listIndex = $client->modeParam('listIndex');

	if (defined $header) {

		$line1 = $header;

	} else {

		$line1 = Slim::Buttons::Input::List::getExtVal($client, $$valueRef, $listIndex, 'header');

		if ($client->modeParam('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {

			$line1 = $client->string($line1);
		}

		if (ref $client->modeParam('headerValue') eq "CODE") {

			$line1 .= Slim::Buttons::Input::List::getExtVal($client, $$valueRef, $listIndex, 'headerValue');
		}
	}
	
	$min = $client->modeParam('min') || 0 unless defined $min;
	$mid = $client->modeParam('mid') || 0 unless defined $mid;
	$max = $client->modeParam('max') || 100 unless defined $max;

	my $val = $max == $min ? 0 : int(($$valueRef - $min)*100/($max-$min));
	my $fullstep = 1 unless $client->modeParam('smoothing');

	$line2 = $client->sliderBar($client->displayWidth(), $val,$max == $min ? 0 :($mid-$min)/($max-$min)*100,$fullstep);

	if ($client->linesPerScreen() == 1) {

		if ($client->modeParam('barOnDouble')) {

			$line1 = $line2;
			$line2 = '';

		} else {

			$line2 = $line1;
		}
	}

	my ($overlay1, $overlay2) = Slim::Buttons::Input::List::getExtVal($client, $valueRef, $listIndex, 'overlayRef') unless $noOverlay;

	$overlay1 = $client->symbols($overlay1) if defined($overlay1);
	$overlay2 = $client->symbols($overlay2) if defined($overlay2);
	
	my $parts = {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ $overlay1, $overlay2 ]
	};

	return $parts;
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	#my $setMethod = shift;

	#possibly skip the init if we are popping back to this mode
	#if ($setMethod ne 'pop') {

		if (!init($client)) {
			Slim::Buttons::Common::popModeRight($client);
		}
	#}

	$client->lines( $client->modeParam('lines') || \&lines );
}

sub exitInput {
	my ($client, $exitType) = @_;

	my $callbackFunct = $client->modeParam('callback');

	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {

		if ($exitType eq 'right') {

			$client->bumpRight();

		} elsif ($exitType eq 'left') {

			Slim::Buttons::Common::popModeRight($client);

		} else {

			Slim::Buttons::Common::popMode($client);
		}

		return;
	}

	$callbackFunct->(@_);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::Settings>

L<Slim::Display::Display>

=cut

1;
