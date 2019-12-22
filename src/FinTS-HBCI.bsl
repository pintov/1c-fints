Function GetVersion() Export

	Return 1;

EndFunction

Procedure Test20010020() Export
	
	Client = CreateClient(
	    "20010020",
	    "9999999999",
	    "11111",
	    "https://hbci.postbank.de/banking/hbci.do");
		
	Accounts = GetSepaAccounts(Client);
	
	Statement = GetStatement(Client, accounts[0], '20010101', CurrentDate());
	
EndProcedure

Procedure Test12345678() Export
	
	Client = CreateClient(
	    "12345678",
	    "test1",
	    "12345",
	    "http://127.0.0.1:3000/cgi-bin/hbciservlet");
		
	Accounts = GetSepaAccounts(Client);
	
	Statement = GetStatement(Client, accounts[0], '20010101', CurrentDate());
	
EndProcedure

Function CreateClient(blz, username, pin, server) Export
	
	self = New Structure("blz,username,pin,systemid,connection,accounts");
	self.blz = blz;
	self.username = username;
	self.pin = pin;
	self.systemid = 0;
	self.connection = New Structure("url", server);
	self.accounts = New Array;

	Return self;
	
EndFunction

Function GetSepaAccounts(self) Export
	
	dialog = Dialog(self.blz, self.username, self.pin, self.systemid, self.connection);
	Dialog_sync(dialog);	
	Dialog_init(dialog);
	
	segments = New Array;
	segments.Add(HKSPA(3, Undefined, Undefined, Undefined));	
	msg_spa = Msg(self.blz, self.username, self.pin, dialog.systemid, dialog.dialogid, dialog.msgno, segments, dialog.tan_mechs);
	resp = Dialog_send(dialog, msg_spa);
	Dialog_end(dialog);
	
	accountsTxt = Response_find_segment(resp, "HISPA");
	accountList = StrSplit(accountsTxt, "+");
	
	self.accounts = New Array;
	
	For i = 1 To accountList.UBound() Do
		accTxt = accountList[i];
		arr = StrSplit(accTxt, ":");
		SEPAAccount = New Structure("iban,bic,accountnumber,subaccount,blz");
		SEPAAccount.iban = arr[1]; 
		SEPAAccount.bic = arr[2];
		SEPAAccount.accountnumber = arr[3]; 
		SEPAAccount.subaccount=arr[4]; 
		SEPAAccount.blz=arr[6];
		self.accounts.Add(SEPAAccount);
	EndDo;
	
	Return self.accounts; 

EndFunction

Function GetStatement(self, account, start_date, end_date) Export

	dialog = Dialog(self.blz, self.username, self.pin, self.systemid, self.connection);
	Dialog_sync(dialog);	
	Dialog_init(dialog);
	
	hversion = dialog.hkkazversion;
	If hversion = 4 Or hversion = 5 Or hversion = 6 Then
		acc = JoinColon(account.accountnumber, account.subaccount, 280, account.blz);
	ElsIf hversion = 7 Then 
		acc = JoinColon(account.iban, account.bic, account.accountnumber, account.subaccount, 280, account.blz);
	Else
		Raise "get_statement: Unsupported HKKAZ version " + hversion;
	EndIf;
	
	responses = New Array;
	
	touchdown_counter = 1;
	segments = New Array;
	segments.Add(HKKAZ(3, hversion, acc, start_date, end_date, Undefined));	
	msg_spa = Msg(self.blz, self.username, self.pin, dialog.systemid, dialog.dialogid, dialog.msgno, segments, dialog.tan_mechs);
	resp = Dialog_send(dialog, msg_spa);
	touchdowns = Response_get_touchdowns(resp, msg_spa);
	responses.Add(resp);
	
	While touchdowns.Get("HKKAZ") <> Undefined Do
		touchdown_counter = touchdown_counter + 1;
		segments = New Array;
		segments.Add(HKKAZ(3, hversion, acc, start_date, end_date, touchdowns.Get("HKKAZ")));	
		msg_spa = Msg(self.blz, self.username, self.pin, dialog.systemid, dialog.dialogid, dialog.msgno, segments, dialog.tan_mechs);
		resp = Dialog_send(dialog, msg_spa);
		touchdowns = Response_get_touchdowns(resp, msg_spa);
		responses.Add(resp);
	EndDo;
	
	Dialog_end(dialog);

	RegExp = RegExp("[^@]*@([0-9]+)@([\s,\S]+)", True);
	statement = New Array;
	For Each resp In responses Do
		
		seg = Response_find_segment(resp, "HIKAZ");
		If seg = Undefined Then
			Continue;		
		EndIf;
		
		Matches = RegExp.Execute(seg);
		If Matches.Count() = 0 Then
			Continue;
		EndIf;
		
		statementData = Matches.Item(0).SubMatches.Item(1);
		statementData = StrReplace(statementData, "@@", Chars.CR+Chars.LF);
		statementData = StrReplace(statementData, "-0000", "+0000");
		
		part = ParseMT940(statementData);
		For Each tr In part Do
			statement.Add(tr);
		EndDo;
		
	EndDo;
	
	Return statement;

EndFunction

#Region Common_functions
Function Subst(Val LookupString,
	Val Parameter1, Val Parameter2 = Undefined, Val Parameter3 = Undefined,
	Val Parameter4 = Undefined, Val Parameter5 = Undefined, Val Parameter6 = Undefined,
	Val Parameter7 = Undefined, Val Parameter8 = Undefined, Val Parameter9 = Undefined)
	
	Result = "";
	Position = Find(LookupString, "%");
	While Position > 0 Do 
		Result = Result + Left(LookupString, Position - 1);
		CharAfterPercent = Mid(LookupString, Position + 1, 1);
		SetParameter = "";
		If CharAfterPercent = "1" Then
			SetParameter =  Parameter1;
		ElsIf CharAfterPercent = "2" Then
			SetParameter =  Parameter2;
		ElsIf CharAfterPercent = "3" Then
			SetParameter =  Parameter3;
		ElsIf CharAfterPercent = "4" Then
			SetParameter =  Parameter4;
		ElsIf CharAfterPercent = "5" Then
			SetParameter =  Parameter5;
		ElsIf CharAfterPercent = "6" Then
			SetParameter =  Parameter6;
		ElsIf CharAfterPercent = "7" Then
			SetParameter =  Parameter7
		ElsIf CharAfterPercent = "8" Then
			SetParameter =  Parameter8;
		ElsIf CharAfterPercent = "9" Then
			SetParameter =  Parameter9;
		EndIf;
		If SetParameter = "" Then
			Result = Result + "%";
			LookupString = Mid(LookupString, Position + 1);
		Else
			Result = Result + SetParameter;
			LookupString = Mid(LookupString, Position + 2);
		EndIf;
		Position = Find(LookupString, "%");
	EndDo;
	Result = Result + LookupString;
	
	Return Result;
EndFunction

Function NumToStr(Value)
	If TypeOf(Value) = Type("Number") Then	
		Return XMLString(Value);
	Else
		Return Value;		
	EndIf;
EndFunction

Function YYYYMMDD(DateTime)
	Return Format(DateTime, "DF=yyyyMMdd");
EndFunction

Function HHMMSS(DateTime)
	Return Format(DateTime, "DF=HHmmss");	
EndFunction

Function JoinColon(Val p1, Val p2,
	Val p3 = Undefined, Val p4 = Undefined, Val p5 = Undefined, Val p6 = Undefined)
	
	p1 = NumToStr(p1);
	p2 = NumToStr(p2);
	p3 = NumToStr(p3);
	p4 = NumToStr(p4);
	p5 = NumToStr(p5);
	p6 = NumToStr(p6);
	
	arr = New Array; 
	arr.Add(p1); 
	arr.Add(p2);
	If p3 <> Undefined Then
		arr.Add(p3);
	EndIf;
	If p4 <> Undefined Then
		arr.Add(p4);
	EndIf;
	If p5 <> Undefined Then
		arr.Add(p5);
	EndIf;
	If p6 <> Undefined Then
		arr.Add(p6);
	EndIf;
	Return StrConcat(arr, ":");

EndFunction

Function RegExp(Pattern, MultiLine = False)
	res = New COMObject("VBScript.RegExp");
	res.IgnoreCase = False;
	res.Global = True;
	res.MultiLine = MultiLine;
	res.Pattern = Pattern;
	Return res; 
EndFunction

Function ParseURL(Val URL)
	
	res = New Structure("Protocol,Host,Port,ResourceAddress");
	
	RegExp = RegExp("^(.*:)\/\/([A-Za-z0-9\-\.]+)(:[0-9]+)?(.*)$");
	Matches = RegExp.Execute(URL);
	If Matches.Count() = 0 Then
		Raise "ParseURL: Wrong URL: " + URL;
	EndIf;

	res.Protocol = Matches.Item(0).SubMatches.Item(0);
	res.Protocol = Lower(StrReplace(res.Protocol, ":", ""));
	res.Host = Matches.Item(0).SubMatches.Item(1);
	res.Port = Matches.Item(0).SubMatches.Item(2);
	If res.Port <> Undefined  Then
		res.Port = Number(StrReplace(res.Port, ":", ""));
	EndIf;	
	res.ResourceAddress = Matches.Item(0).SubMatches.Item(3);
	
	If Not ValueIsFilled(res.Port) Then
		If res.Protocol = "https" Then
			res.Port = 443;
		ElsIf res.Protocol = "http" Then
			res.Port = 80;
		Else
			Raise "ParseURL: Empty port and unknown protocol: " + res.Protocol;
		EndIf;
	EndIf;
	
	Return res;
		
EndFunction

Function CreateHTTPConnection(URL)

	If URL.Protocol = "https" Then
		Return New HTTPConnection(URL.Host, URL.Port, , , , , New OpenSSLSecureConnection());
	ElsIf URL.Protocol = "http" Then
		Return New HTTPConnection(URL.Host, URL.Port);
	Else
		Raise "CreateHTTPConnection: Unknown protocol: " + URL.Protocol;
	EndIf;
	
EndFunction
#EndRegion

#Region MT940
Function ParseDateYYMMDD(Val Date)
	
	Try
		y = Number(Mid(Date, 1, 2)) + 2000;
		m = Number(Mid(Date, 3, 2));
		d = Number(Mid(Date, 5, 2));
		res = Date(y, m, d, 0, 0, 0);
	Except
		Raise "ParseDateYYMMDD: wrong date: " + Date;
	EndTry;
	Return res;
	
EndFunction

Function ParseMT940_TagValue(data, Matches, i)

	tagsCount = Matches.Count();
	begItem = Matches.Item(i);
	beg = begItem.FirstIndex + begItem.Length + 1;
	If i + 1 = tagsCount Then
		end = StrLen(data);
	Else
		end = Matches.Item(i+1).FirstIndex;
	EndIf;
	Return Mid(data, beg, end - beg);
	
EndFunction

Function ParseMT940_Parse60F62F(TagValue)

	RegEx60F62F = RegExp("^([C|D]{1})([0-9]{6})([A-Z]{3})([0-9]+,[0-9]{2})");
	
	Matches = RegEx60F62F.Execute(TagValue);
	tagsCount = Matches.Count();
	If tagsCount = 0 Then
		Raise "ParseMT940_Parse60F62F: Wrong tag value: " + TagValue;
	EndIf;
	
	SubMatches = Matches.Item(0).SubMatches;
	res = New Structure("DtCr,EntryDate,CurrencyCode,Balance");
	Try
		res.DtCr = 			SubMatches.Item(0);
		res.EntryDate = 	SubMatches.Item(1);
		res.CurrencyCode =	SubMatches.Item(2);
		res.Balance = 		SubMatches.Item(3);
	Except
		Raise "ParseMT940_Parse60F62F: Wrong tag value: " + TagValue;
	EndTry;
	
	res.EntryDate = ParseDateYYMMDD(res.EntryDate);
	Try
		res.Balance = StrReplace(res.Balance, ",", ".");
		res.Balance = Number(res.Balance);
	Except
		Raise "ParseMT940_Parse60F62F: Wrong Balance value: " + res.Balance;
	EndTry;
	
	Return res;

EndFunction

Function ParseMT940_Parse61(TagValue)

	RegEx61 = RegExp("^([0-9]{6})([0-9]{4})?([C|D]{1})([A-Z]{1})?([0-9]+,[0-9]{2})([A-Z0-9]{4})([A-Z0-9]+)");
	
	Matches = RegEx61.Execute(TagValue);
	tagsCount = Matches.Count();
	If tagsCount = 0 Then
		Raise "ParseMT940_Parse61: Wrong tag value: " + TagValue;
	EndIf;
	
	SubMatches = Matches.Item(0).SubMatches;
	res = New Structure("ValueDate,EntryDate,DtCr,CapitalCode,Amount,Type,Reference");
	Try
		res.ValueDate = 	SubMatches.Item(0);
		res.EntryDate = 	SubMatches.Item(1);
		res.DtCr =			SubMatches.Item(2);
		res.CapitalCode = 	SubMatches.Item(3);
		res.Amount = 		SubMatches.Item(4);
		res.Type =			SubMatches.Item(5);
		res.Reference = 	SubMatches.Item(6);
	Except
		Raise "ParseMT940_Parse60F62F: Wrong tag value: " + TagValue;
	EndTry;
	
	res.ValueDate = ParseDateYYMMDD(res.ValueDate);
	Try
		res.Amount = StrReplace(res.Amount, ",", ".");
		res.Amount = Number(res.Amount);
	Except
		Raise "ParseMT940_Parse61: Wrong Amount value: " + res.Amount;
	EndTry;
	
	Return res;

EndFunction

Function ParseMT940(data)
	
	RegExTags = RegExp("^:(([0-9]{2}|NS)([A-Z])?):", True);
	Matches = RegExTags.Execute(data);
	tagsCount = Matches.Count();
	If tagsCount = 0 Then
		Raise "ParseMT940: Wrong data";
	EndIf;
	
	statement = New Array;
	i = 0;
	While i < tagsCount Do
		Tag = Matches.Item(i).Value;
		If Tag <> ":20:" Then
			i = i + 1;
			Continue;
		EndIf;
		
		tr = New Structure("OpeningBalance,ClosingBalance,StatementLine,Description");
		i = i + 1;
		While i < tagsCount Do
			
			Tag = Matches.Item(i).Value;
			Value = ParseMT940_TagValue(data, Matches, i);
			
			If Tag = ":20:" Then
			    Break;
				
			ElsIf Tag = ":60F:" Then // Opening balance
				tr.OpeningBalance =  ParseMT940_Parse60F62F(Value);
				
			ElsIf Tag = ":61:" Then // Statement line
				tr.StatementLine = ParseMT940_Parse61(Value);				
				
			ElsIf Tag = ":62F:" Then  // Closing balance
				tr.ClosingBalance = ParseMT940_Parse60F62F(Value);
				
			ElsIf Tag = ":86:" Then
				tr.Description = Value;
				
			EndIf;
			i = i + 1;
		EndDo;
		
		statement.Add(tr);
		
	EndDo;
	
	Return statement;
	
EndFunction
#EndRegion

#Region Segments
Function Segment(type, version, segmentno)
	self = New Structure("country_code,type,version,segmentno,data");
	self.country_code = 280;
	self.type = type;
    self.version = version;
	self.segmentno = segmentno;
	Return self
EndFunction

Function Segment_str(self)

    res = JoinColon(self.type, self.segmentno, self.version);
	For Each d In self.data Do
		d = NumToStr(d);
        res = res + "+" + d;
	EndDo;
	res = res + "'";
	Return res;

EndFunction

Function HNHBK(msglen, dialogid, msgno)
	
	HEADER_LENGTH = 29;
	
	self = Segment("HNHBK", 3, 1);

	If StrLen(NumToStr(msglen)) <> 12 Then
		msglen = msglen + HEADER_LENGTH + StrLen(NumToStr(dialogid)) + StrLen(NumToStr(msgno));
		msglen = Format(msglen, "ND=12; NLZ=; NG=")
	EndIf;
	
	self.data = New Array;
	self.data.Add(msglen);
	self.data.Add(300);
	self.data.Add(dialogid);
	self.data.Add(msgno);
	return self;
	
EndFunction

Function HKIDN(segmentno, blz, username, systemid = 0, customerid = 1)

	//Identifikation
	//Section C.3.1.2
	
	self = Segment("HKIDN", 2, segmentno);
	data = New Array;
	data.Add(JoinColon(self.country_code, blz));
	data.Add(username);
	data.Add(systemid);
	data.Add(customerid);
	self.data = data;	
	return self;

EndFunction

Function HKVVB(segmentno, lang = 1)

	//Verarbeitungsvorbereitung
	//Section C.3.1.3
	
	//LANG_DE = 1 - default
	//LANG_EN = 2
	//LANG_FR = 3
	
    PRODUCT_NAME = "1cfints";
    PRODUCT_VERSION = "0.1";
	
	self = Segment("HKVVB", 3, segmentno);
	data = New Array;
	data.Add(0);
	data.Add(0);
	data.Add(lang);
	data.Add(PRODUCT_NAME);
	data.Add(PRODUCT_VERSION);
	self.data = data;
	return self;
	
EndFunction

Function HKSYN(segmentno, mode = 0)

	//Synchronisation
	//Section C.8.1.2
	
	//SYNC_MODE_NEW_CUSTOMER_ID = 0
	//SYNC_MODE_LAST_MSG_NUMBER = 1
	//SYNC_MODE_SIGNATURE_ID = 2
	
	self = Segment("HKSYN", 3, segmentno);
	self.data = New Array;
	self.data.Add(mode);
	return self;
	
EndFunction

Function HNSHK(segmentno, secref, blz, username, systemid, profile_version, security_function = 999) 

	//Signaturkopf
	//Section B.5.1
	
	currDate = CurrentDate();
	
	SECURITY_FUNC = 999;
	SECURITY_BOUNDARY = 1; // SHM
	SECURITY_SUPPLIER_ROLE = 1;  // ISS
	
	self = Segment("HNSHK", 4, segmentno);
	data = New Array;
	data.Add(JoinColon("PIN", profile_version));
	data.Add(security_function);
	data.Add(secref);
	data.Add(SECURITY_BOUNDARY);
	data.Add(SECURITY_SUPPLIER_ROLE);
	data.Add(JoinColon("1", "", systemid));
	data.Add(1);
	data.Add(JoinColon("1", YYYYMMDD(currDate), HHMMSS(currDate)));
	data.Add(JoinColon("1", "999", "1    ")); // Negotiate hash algorithm
	data.Add(JoinColon("6", "10", "16")); // RSA mode
	data.Add(JoinColon(self.country_code, blz, username, "S", "0", "0"));
	
	self.data = data;
	return self;
	
EndFunction

Function HNVSK(segmentno, blz, username, systemid, profile_version) 

	//Verschlüsslungskopf
	//Section B.5.3
	
	currDate = CurrentDate();
	
    COMPRESSION_NONE = 0;
    SECURITY_SUPPLIER_ROLE = 1;  // ISS
	
	self = Segment("HNVSK", 3, segmentno);
	data = New Array;
	data.Add(JoinColon("PIN", profile_version));
	data.Add(998);	
	data.Add(SECURITY_SUPPLIER_ROLE);	
	data.Add(JoinColon("1", "", systemid));	
	data.Add(JoinColon("1", YYYYMMDD(currDate), HHMMSS(currDate)));
	data.Add(JoinColon("2", "2", "13", "@8@00000000", "5", "1")); // Crypto algorithm	
	data.Add(JoinColon(self.country_code, blz, username, "S", "0", "0"));	
	data.Add(COMPRESSION_NONE);	
	self.data = data;
	return self;
	
EndFunction

Function HNVSD(segmentno, encoded_data)
	
	//Verschlüsselte Daten
	//Section B.5.4
	
	self = Segment("HNVSD", 1, segmentno);
	self.Insert("encoded_data", encoded_data);
	self.data = New Array;
	self.data.Add(Subst("@%1@%2", StrLen(encoded_data), encoded_data));
	return self;
	
EndFunction

Function HNVSD_set_data(self, encoded_data)

	self.encoded_data = encoded_data;
	self.data = New Array;
	self.data.Add(Subst("@%1@%2", StrLen(encoded_data), encoded_data));
	return self;

EndFunction

Function HNSHA(segmentno, secref, pin)
	
	//Signaturabschluss
	//Section B.5.2
	
    SECURITY_FUNC = 999;
    SECURITY_BOUNDARY = 1;  // SHM
    SECURITY_SUPPLIER_ROLE = 1;  // ISS
    PINTAN_VERSION = 1;  // 1-step
	
	self = Segment("HNSHA", 2, segmentno);
	self.data = New Array;
	self.data.Add(secref);
	self.data.Add("");
	self.data.Add(pin);
	return self;
	
EndFunction

Function HNHBS(segmentno, msgno)
	
	//Nachrichtenabschluss
	//Section B.5.3
	
	self = Segment("HNHBS", 1, segmentno);
	self.data = New Array;
	self.data.Add(msgno);
	return self;
	
EndFunction

Function HKEND(segmentno, dialogid)

	//Dialogende
	//Section C.4.1.2
	
	self = Segment("HKEND", 1, segmentno);
	self.data = New Array;
	self.data.Add(dialogid);
	return self;

EndFunction

Function HKSPA(segmentno, accno, subaccfeature, blz)

	//SEPA-Kontoverbindung anfordern
	//Section C.10.1.3
	
	self = Segment("HKSPA", 1, segmentno);
	
	self.data = New Array;
	
	If accno = Undefined Then
		self.data.Add("");
	Else
		self.data.Add(JoinColon(accno, subaccfeature, self.country_code, blz));		
	EndIf;
	
	return self;

EndFunction

Function HKKAZ(segmentno, version, account, date_start, date_end, touchdown)

	//Kontoumsätze
	//Section C.2.1.1.1.2
	
	self = Segment("HKKAZ", 1, segmentno);
	self.version = version;
	
	self.data = New Array;
	self.data.Add(account);
	self.data.Add("N");
	self.data.Add(YYYYMMDD(date_start));
	self.data.Add(YYYYMMDD(date_end));
	self.data.Add("");
	If touchdown = Undefined Then
		self.data.Add("");
	Else
		self.data.Add(touchdown);		
	EndIf;
	
	return self;

EndFunction
#EndRegion

#Region Message
Function Msg(blz, username, pin, systemid, dialogid, msgno, segments, tan_mechs = Undefined)

	self = New Structure("blz,username,pin,systemid,dialogid,msgno,segments,encrypted_segments,profile_version,security_function,enc_envelop");
	self.blz = blz;
	self.username = username;
	self.pin = pin;
	self.systemid = systemid;
	self.dialogid = dialogid;
	self.msgno = msgno;
	self.segments = New Array;
	self.encrypted_segments = New Array;
	
	If tan_mechs <> Undefined And tan_mechs.Find("999") = Undefined Then
		self.profile_version = 2;
		self.security_function = tan_mechs[0];
	Else
		self.profile_version = 1;
		self.security_function = "999";
	EndIf;
	
	sig_head = Msg_build_signature_head(self);
	enc_head = Msg_build_encryption_head(self);

	self.segments.Add(enc_head);
	self.enc_envelop = HNVSD(999, "");
	self.segments.Add(self.enc_envelop);
	
	Msg_append_enc_segment(self, sig_head);
	For Each s In segments Do
		Msg_append_enc_segment(self, s);
	EndDo;
	
	cur_count = segments.Count() + 3;
	
	sig_end = HNSHA(cur_count, self.secref, self.pin);
	Msg_append_enc_segment(self, sig_end);
	
	self.segments.Add(HNHBS(cur_count + 1, self.msgno));
	
	Return self;
	
EndFunction

Function Msg_build_signature_head(self)
	
	rand = New RandomNumberGenerator(); 
	self.Insert("secref", rand.RandomNumber(1000000, 9999999));
	
	res = HNSHK(2, self.secref, self.blz, self.username, self.systemid, self.profile_version, self.security_function);
	
	Return res;
		
EndFunction

Function Msg_build_encryption_head(self)

	Return HNVSK(998, self.blz, self.username, self.systemid, self.profile_version);

EndFunction

Function Msg_append_enc_segment(self, seg)

	self.encrypted_segments.Add(seg);
	HNVSD_set_data(self.enc_envelop, self.enc_envelop.encoded_data + Segment_str(seg));	

EndFunction

Function Msg_build_header(self)
	
	 l = 0;
	 For Each s In self.segments Do
		 l = l + StrLen(Segment_str(s));
	 EndDo;
		 
     Return HNHBK(l, self.dialogid, self.msgno)
	
EndFunction

Function Msg_str(self)

	header = Msg_build_header(self);
	
	res = Segment_str(header);
	For Each s In self.segments Do
		res = res + Segment_str(s); 	
	EndDo;
	
	Return res;
	
EndFunction
#EndRegion

#Region Response
Function Send(conn, msg)

	URL = ParseURL(conn.url);
	connection = CreateHTTPConnection(URL);	
	
	txt = Msg_str(msg);
	tmp1 = GetTempFileName("txt");	
	file = New TextWriter(tmp1, "ISO-8859-1"); 
	file.Write(txt);
	file.Close();
	
	data = New BinaryData(tmp1);
	base64 = Base64String(data);
	
	request = New HTTPRequest;
	request.Headers.Insert("User-Agent","Subsembly");
	request.Headers.Insert("Content-Type","text/plain");
	request.Headers.Insert("Content-Length", StrLen(base64));
	request.ResourceAddress = URL.ResourceAddress;
	request.SetBodyFromString(base64, "ISO-8859-1");
		
	respBase64 = connection.Post(request).GetBodyAsString("ISO-8859-1");
	respBinary = Base64Value(respBase64);
	tmp2 = GetTempFileName("txt");	
	respBinary.Write(tmp2);
	file = New TextReader(tmp2, "ISO-8859-1"); 
	data = file.Read();
	data = StrReplace(data, Char(0), " ");
	file.Close();
	
	Try
	    DeleteFiles(tmp1);
	    DeleteFiles(tmp2);
	Except
	EndTry;
	
	Return data;

EndFunction

Function Response(data)

	//RE_UNWRAP = re.compile('HNVSD:\d+:\d+\+@\d+@(.+)\'\'')
	//RE_SEGMENTS = re.compile("'(?=[A-Z]{4,}:\d|')")
	//RE_SYSTEMID = re.compile("HISYN:\d+:\d+:\d+\+(.+)")
	//RE_TANMECH = re.compile('\d{3}')

	self = New Structure("response,segments");
    self.response = Response_unwrap(self, data);
	self.segments = Response_segments(self, data);
	
	Return self;

EndFunction

Function Response_unwrap(self, data)
	
	RegExp = RegExp("HNVSD:\d+:\d+\+@\d+@(.+)''");
	Matches = RegExp.Execute(data);
	If Matches.Count() = 0 Then
		Return data;
	Else
		Return Matches.Item(0).Value;
	EndIf;

EndFunction

Function Response_segments(self, data)
	
	res = New Array;
	RegExp = RegExp("'(?=[A-Z]{4,}:\d|')");
	
	Matches = RegExp.Execute(data);
	pos = 1;
	For i = 0 To Matches.Count() - 1 Do
		count = Matches.Item(i).FirstIndex - pos + 1;
		str = Mid(data, pos, count);
		res.Add(str);
		pos = Matches.Item(i).FirstIndex + 2; 
	EndDo;
	
	count = StrLen(data) - pos + 1;
	str = Mid(data, pos, count);
	res.Add(str);
	
	Return res;

EndFunction

Function Response_is_success(self)
	
	summary = Response_get_summary_by_segment(self, "HIRMG");
	For Each s in summary Do
		If Left(s.Key, 1) = "9" Then
			Return False;
		EndIf;
	EndDo;
	Return True;

EndFunction

Function Response_get_summary_by_segment(self, name)
		
    If name <> "HIRMS" And name <> "HIRMG" Then
        Raise "Unsupported segment for message summary";
	EndIf;
	
	res = New Map;
	seg = Response_find_segment(self, name);
	segPrts = StrSplit(seg, "+");
	For n = 1 To segPrts.UBound() Do
		prt = segPrts[n]; 
		de = StrSplit(prt, ":");
		res.Insert(de[0], de[2]);
	EndDo;
	
	Return res;
	
EndFunction

Function Response_find_segment(self, name)
	Return Response_find_segments(self, name, True);
EndFunction

Function Response_find_segments(self, name, one = False)

	found = New Array;
	If one Then
		found = Undefined;
	EndIf;

	For Each s In self.segments Do
		spl = StrSplit(s, ":");
        If spl[0] = name Then
            If one Then
                Return s;
			Else
            	found.Add(s);
			EndIf;
		EndIf;
	EndDo;
	
	Return found;
	
EndFunction

Function Response_get_systemid(self)
	
	seg = Response_find_segment(self, "HISYN");
	RegExp = RegExp("HISYN:\d+:\d+:\d+\+(.+)");
	Matches = RegExp.Execute(seg);
	If Matches.Count() = 0 Then
		Raise "Could not find systemid";
	Else
		Return Matches.Item(0).SubMatches.Item(0);
	EndIf;
	
EndFunction

Function Response_get_dialog_id(self)
	
	seg = Response_find_segment(self, "HNHBK");
	If seg = Undefined Then
		Raise "get_dialog_id: Invalid response, no HNHBK segment";
	EndIf;
	
	Return Response_get_segment_index(self, 4, seg);
	
EndFunction

Function Response_get_segment_index(self, idx, seg)
	
	spl = StrSplit(seg, "+");
	
	If spl.Count() < idx Then
		Return Undefined;
	EndIf;
	
	Return spl[idx - 1];
	
EndFunction

Function Response_get_bank_name(self)
	
	seg = Response_find_segment(self, "HIBPA");
	If seg = Undefined Then
		Raise "Invalid response, no HIBPA segment";
	EndIf;
	
	spl = StrSplit(seg, "+");
	If spl.Count() < 4 Then
		Return Undefined;
	EndIf;

	return spl[3];
	
EndFunction

Function Response_get_segment_max_version(self, name)	
	v = 3;
	segs = Response_find_segments(self, name);
	For Each s In segs Do
		parts = StrSplit(s, "+");
		segheader = StrSplit(parts[0], ":");
		curver = Number(segheader[2]);
		If curver > v Then
			v =	curver;	
		EndIf;
	EndDo;	
	Return v;	
EndFunction

Function Response_get_supported_tan_mechanisms(self)
	segs = Response_find_segments(self, "HIRMS");
	For Each s In segs Do
		seg = StrSplit(s, "+");
		For i = 1 to seg.UBound() Do
			ss = seg[i];
			id_msg = StrSplit(ss, ":");
			If id_msg[0] = "3920" Then
				RegExp = RegExp("\d{3}");
				Matches = RegExp.Execute(id_msg[3]);
				If Matches.Count() > 0 Then
					res = New Array;
					res.Add(Matches.Item(0).Value);
					Return res;
				EndIf;
			EndIf;
		EndDo;
	EndDo;
	Return False;	
EndFunction

Function Response_find_segment_for_reference(self, name, ref)
	segs = Response_find_segments(self, name);
	For Each seg In segs Do
		segsplit = StrSplit(StrSplit(seg, "+")[0], ":");
		If segsplit[3] = NumToStr(ref.segmentno) Then
			Return seg;
		EndIf;
	EndDo;
	Return Undefined;
EndFunction

Function Response_get_touchdowns(self, msg)
	
	touchdown = New Map;
	For Each msgseg In msg.encrypted_segments Do
		seg = Response_find_segment_for_reference(self, "HIRMS", msgseg);						
		If seg = Undefined Then
			Continue;		
		EndIf;
		parts = StrSplit(seg, "+");
		For i = 1 To parts.UBound() Do
			psplit = StrSplit(parts[i], ":");
			If psplit[0] = "3040" Then
				touchdown.Insert(msgseg.type, psplit[3]);
			EndIf;
		EndDo;
	EndDo;
	Return touchdown;

EndFunction
#EndRegion

#Region Dialog
Function Dialog(blz, username, pin, systemid, connection)

	self = New Structure("blz,username,pin,systemid,connection,msgno,dialogid,hksalversion,hkkazversion,tan_mechs,bankname");
    self.blz = blz;
    self.username = username;
    self.pin = pin;
    self.systemid = systemid;
    self.connection = connection;
    self.msgno = 1;
    self.dialogid = 0;
    self.hksalversion = 6;
    self.hkkazversion = 6;
    self.tan_mechs = new Array;
	
	Return self;

EndFunction

Function Dialog_send(self, msg)
	                                    
	msg.msgno = self.msgno;
	msg.dialogid = self.dialogid;
	
	data = Send(self.connection, msg);
	
	resp = Response(data);
	
	If Not Response_is_success(resp) Then
		arr = New Array;
		kvs = Response_get_summary_by_segment(resp, "HIRMG");
		For Each kv In kvs Do
			arr.Add(kv.Value);
		EndDo;
		kvs = Response_get_summary_by_segment(resp, "HIRMS");
		For Each kv In kvs Do
			arr.Add(kv.Value);
		EndDo;
		errorMsg = StrConcat(arr, "; ");
		Raise errorMsg;
	EndIf;
	self.msgno = self.msgno + 1;
	
	return resp;

EndFunction

Function Dialog_end(self)

	segments = New Array;
	segments.Add(HKEND(3, self.dialogid));
	
	msg_end = Msg(self.blz, self.username, self.pin, self.systemid, self.dialogid, self.msgno, segments);
	
	resp = Dialog_send(self, msg_end);
    self.dialogid = 0;
    self.msgno = 1;
    return resp;

EndFunction

Function Dialog_sync(self)

	seg_identification = HKIDN(3, self.blz, self.username, 0);
	seg_prepare = HKVVB(4);        
	seg_sync = HKSYN(5);
	
	segments = New Array;
	segments.Add(seg_identification);
	segments.Add(seg_prepare);
	segments.Add(seg_sync);
	
	msg_sync = Msg(self.blz, self.username, self.pin, self.systemid, self.dialogid, self.msgno, segments);
	
	resp = Dialog_send(self, msg_sync);
	self.systemid = Response_get_systemid(resp);
	self.dialogid = Response_get_dialog_id(resp);
    self.bankname = Response_get_bank_name(resp);
	self.hksalversion = Response_get_segment_max_version(resp, "HISALS");
    self.hkkazversion = Response_get_segment_max_version(resp, "HIKAZS");
	self.tan_mechs = Response_get_supported_tan_mechanisms(resp);
	Dialog_end(self);
	
EndFunction

Function Dialog_init(self)
	
    seg_identification = HKIDN(3, self.blz, self.username, self.systemid);
	seg_prepare = HKVVB(4);
	
	segments = New Array;
	segments.Add(seg_identification);
	segments.Add(seg_prepare);
	
	msg_init = Msg(self.blz, self.username, self.pin, self.systemid, self.dialogid, self.msgno, segments, self.tan_mechs);
	resp = Dialog_send(self, msg_init);
	self.dialogid = Response_get_dialog_id(resp);
	
	Return self.dialogid;

EndFunction
#EndRegion
