use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(10);
#	waitstillimage(60,290);
	mouse_hide();
	waitgoodimage(300);

        sendkey "shift-tab"; # skip media check
	sendkey "ret";


}

1;