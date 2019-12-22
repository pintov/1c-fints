1C:Enterprise 8 FinTS / HBCI
=======

This is a pure-1C implementation of FinTS (formerly known as HBCI), an
online-banking protocol commonly supported by German banks.

Limitations
-----------

* Only FinTS 3.0 is supported
* Only PIN/TAN authentication is supported, no signature cards
* Only a number of reading operations are currently supported


Usage
-----

```bsl
	Client = FinTS.CreateClient(
	    "12345678",		// Your bank's BLZ
	    "test1",		// User ID
	    "12345",		// PIN
	    "http://127.0.0.1:3000/cgi-bin/hbciservlet");
		
	Accounts = FinTS.GetSepaAccounts(Client);
	
	Statement = FinTS.GetStatement(Client, accounts[0], '20010101', CurrentDate());
```

Credits and License
-------------------

Author: Vasily Pintov <vasily@pintov.ru>

License: LGPL

This is a quite close port of the [python-fints](https://github.com/raphaelm/python-fints)
implementation that was released by Raphael Michel under the LGPL license.
Thanks for your work!
