MODULE_NAME='mExtronSwitch'(DEV vdvControl, DEV dvDevice)
INCLUDE 'CustomFunctions'
/******************************************************************************
	Basic Extron Video Switcher Module - RMS Enabled
******************************************************************************/
DEFINE_TYPE STRUCTURE uGain{
	INTEGER  MUTE
	INTEGER  GAIN
	INTEGER  GAIN_PEND
	SINTEGER LAST_GAIN
}

DEFINE_TYPE STRUCTURE uSwitch{
	// Communications
	INTEGER 	IP_PORT						//
	CHAR		IP_HOST[255]				//
	INTEGER 	IP_STATE						//
	INTEGER	isIP
	CHAR     PASSWORD[20]

	INTEGER DEBUG					// Debuging ON/OFF
	INTEGER DISABLED				// Disable Module
	INTEGER NOPOLL					// Prevent Polling (for 1Way RS232)
	CHAR	  Tx[1000]				// Transmission Buffer
	CHAR	  LAST_SENT[100]		// Last sent message for feedback handling
	INTEGER MODEL_ID				// Internal Model Constant
	// MetaData
	CHAR META_FIRMWARE[20]		// Firmware Shorthand
	CHAR META_FIRMWARE_FULL[20]// Firmware Longhand
	CHAR META_PART_NUMBER[20]	// Part Number
	CHAR META_MODEL[20]			// Extron Model (Programatically Set based on PN)
	CHAR META_MAC[20]				// MAC Address (If Applicable)
	CHAR META_IP[20]				// IP Address (If Applicable)
	INTEGER HAS_NETWORK			// Does this switch have a network interface
	INTEGER HAS_AUDIO			// Does this switch have audio
	// State
	CHAR DIAG_INT_TEMP[20]		// Internal Temperature
	INTEGER SIGNAL[8]
	// Audio
	uGain AUDIO[2]
}

DEFINE_CONSTANT
LONG TLID_COMMS 	= 1
LONG TLID_POLL	 	= 2
LONG TLID_SEND		= 3
LONG TLID_RETRY	= 4

LONG TLID_GAIN_00	= 10
LONG TLID_GAIN_01	= 11
LONG TLID_GAIN_02	= 12

INTEGER AUDIO_PRO = 1
INTEGER AUDIO_MIC = 2

// IP States
INTEGER IP_STATE_OFFLINE		= 0
INTEGER IP_STATE_CONNECTING	= 1
INTEGER IP_STATE_CONNECTED		= 2

INTEGER MODEL_NA           = 00
INTEGER MODEL_IN1604			= 01
INTEGER MODEL_IN1606 		= 02
INTEGER MODEL_IN1608 		= 03
INTEGER MODEL_IN1608xi 		= 04
INTEGER MODEL_MPS601 		= 05
INTEGER MODEL_MPS602 		= 06
INTEGER MODEL_SW2USB 		= 07
INTEGER MODEL_DTPTUSW233 	= 08
INTEGER MODEL_DTPTUSW333   = 09
INTEGER MODEL_SW2HD4k 		= 10
INTEGER MODEL_SW2HD4kPlus	= 11
INTEGER MODEL_SW4HD4k 		= 12
INTEGER MODEL_SW4HD4kPlus	= 13
INTEGER MODEL_SW4HD4kDTP   = 14
INTEGER MODEL_SW6HD4k 		= 15
INTEGER MODEL_SW6HD4kPlus	= 16
INTEGER MODEL_SW8HD4k 		= 17
INTEGER MODEL_SW8HD4kPlus	= 18
INTEGER MODEL_SW6 			= 19
INTEGER MODEL_SW8 			= 20
INTEGER MODEL_MLAVC10 		= 21
INTEGER MODEL_IN1804 		= 22
INTEGER MODEL_IN1804DI		= 23
INTEGER MODEL_IN1804DO		= 24
INTEGER MODEL_IN1806 		= 25
INTEGER MODEL_IN1808 		= 26

DEFINE_VARIABLE
LONG TLT_COMMS[] 			= { 90000 }
LONG TLT_POLL[] 			= {  5000 }
LONG TLT_SEND[]			= {  2000 }
LONG TLT_GAIN[]			= {   150 }
LONG TLT_RETRY[]			= {  5000 }
VOLATILE uSwitch mySwitch
/******************************************************************************
	Module Startup
******************************************************************************/
DEFINE_START{
	mySwitch.isIP = !(dvDEVICE.NUMBER)
}
/******************************************************************************
	Helper Functions
******************************************************************************/

(** IP Connection Helpers **)
DEFINE_FUNCTION fnOpenTCPConnection(){
	IF(mySwitch.IP_HOST == ''){
		fnDebug(TRUE,'Extron IP','Not Set')
	}
	ELSE{
		fnDebug(FALSE,'Connecting to Extron on ',"mySwitch.IP_HOST,':',ITOA(mySwitch.IP_PORT)")
		mySwitch.IP_STATE = IP_STATE_CONNECTING
		ip_client_open(dvDevice.port, mySwitch.IP_HOST, mySwitch.IP_PORT, IP_TCP)
	}
}
DEFINE_FUNCTION fnCloseTCPConnection(){
	IP_CLIENT_CLOSE(dvDevice.port)
}
DEFINE_FUNCTION fnRetryConnection(){
	IF(TIMELINE_ACTIVE(TLID_RETRY)){TIMELINE_KILL(TLID_RETRY)}
	TIMELINE_CREATE(TLID_RETRY,TLT_RETRY,LENGTH_ARRAY(TLT_RETRY),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
}
DEFINE_EVENT TIMELINE_EVENT[TLID_RETRY]{
	fnOpenTCPConnection()
}

DEFINE_FUNCTION fnDebug(INTEGER FORCE,CHAR Msg[], CHAR MsgData[]){
	 IF(mySwitch.DEBUG || FORCE){
		SEND_STRING 0:0:0, "ITOA(vdvControl.Number),':',Msg, ':', MsgData"
	}
}
DEFINE_FUNCTION fnAddToQueue(CHAR pToSend[255], INTEGER isQuery){
	mySwitch.Tx = "mySwitch.Tx,pToSend,$FF"
	fnSendFromQueue()
	IF(!isQuery){
		fnInitPoll()
	}
}
DEFINE_FUNCTION fnSendFromQueue(){
	IF(!TIMELINE_ACTIVE(TLID_SEND) && LENGTH_ARRAY(mySwitch.Tx)){
		mySwitch.LAST_SENT = fnStripCharsRight(REMOVE_STRING(mySwitch.Tx,"$FF",1),1)
		SEND_STRING dvDevice,mySwitch.LAST_SENT
		fnDebug(FALSE,'AMX->Extron', mySwitch.LAST_SENT);
		TIMELINE_CREATE(TLID_SEND,TLT_SEND,LENGTH_ARRAY(TLT_SEND),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
	}
}
DEFINE_EVENT TIMELINE_EVENT[TLID_SEND]{
	mySwitch.LAST_SENT = ''
	mySwitch.Tx = ''
}

DEFINE_FUNCTION fnInitPoll(){
	IF(!mySwitch.DISABLED){
		IF(TIMELINE_ACTIVE(TLID_POLL)){ TIMELINE_KILL(TLID_POLL) }
		TIMELINE_CREATE(TLID_POLL,TLT_POLL,LENGTH_ARRAY(TLT_POLL),TIMELINE_ABSOLUTE,TIMELINE_REPEAT)
	}
}
DEFINE_EVENT TIMELINE_EVENT[TLID_POLL]{
	IF(!LENGTH_ARRAY(mySwitch.META_PART_NUMBER) || TIMELINE.REPETITION == 8 ){
		fnPollFull()
		fnInitPoll()
	}
	ELSE{
		fnPollShort()
	}
}

DEFINE_FUNCTION fnPollFull(){
	IF(!mySwitch.NOPOLL){
		fnAddToQueue('N',TRUE)
		IF(!LENGTH_ARRAY(mySwitch.META_FIRMWARE)){
			fnAddToQueue('Q',TRUE)
		}
		IF(!LENGTH_ARRAY(mySwitch.META_FIRMWARE_FULL)){
			fnAddToQueue('*Q',TRUE)
		}
		IF(mySwitch.HAS_NETWORK){
			fnAddToQueue("$1B,'1CV',$0D",TRUE)
			IF(!LENGTH_ARRAY(mySwitch.META_MAC)){
				fnAddToQueue("$1B,'CH',$0D",TRUE)
			}
			fnAddToQueue("$1B,'CI',$0D",TRUE)
		}
		ELSE{
			fnPollShort()
			SWITCH(mySwitch.MODEL_ID){
				// Do Nothing
				CASE MODEL_MLAVC10:{}
				// Request Input
				CASE MODEL_MPS601:
				CASE MODEL_MPS602:
				CASE MODEL_DTPTUSW233:
				CASE MODEL_DTPTUSW333:
				CASE MODEL_SW2USB:
				CASE MODEL_SW2HD4k:
				CASE MODEL_SW2HD4kPlus:
				CASE MODEL_SW4HD4k:
				CASE MODEL_SW4HD4kPlus:
				CASE MODEL_SW4HD4kDTP:
				CASE MODEL_SW6HD4k:
				CASE MODEL_SW6HD4kPlus:
				CASE MODEL_SW8HD4k:
				CASE MODEL_SW8HD4kPlus:
				CASE MODEL_SW6:
				CASE MODEL_SW8:{
					fnAddToQueue('I',TRUE)
				}
				DEFAULT:	fnAddToQueue("$1B,'20STAT',$0D",TRUE)
			}
			IF(mySwitch.HAS_AUDIO){
				SWITCH(mySwitch.MODEL_ID){
					CASE MODEL_MLAVC10:
					CASE MODEL_IN1604:
					CASE MODEL_IN1804:
					CASE MODEL_IN1804DI:
					CASE MODEL_IN1804DO:{
						fnAddToQueue('V',TRUE)
						fnAddToQueue('Z',TRUE)
					}
					CASE MODEL_IN1606:
					CASE MODEL_IN1608:
					CASE MODEL_IN1608xi:{
						fnAddToQueue("$1B,'D1GRPM',$0D",TRUE)
						fnAddToQueue("$1B,'D2GRPM',$0D",TRUE)
					}
					CASE MODEL_IN1806:
					CASE MODEL_IN1808:{
						fnAddToQueue("$1B,'D3GRPM',$0D",TRUE)
						fnAddToQueue("$1B,'D4GRPM',$0D",TRUE)
					}
				}
			}
		}
	}
}
DEFINE_FUNCTION fnPollShort(){
	IF(!mySwitch.NOPOLL){
		SWITCH(mySwitch.MODEL_ID){
			CASE MODEL_DTPTUSW233:
			CASE MODEL_DTPTUSW333:
			CASE MODEL_IN1604:
			CASE MODEL_IN1606:
			CASE MODEL_IN1608:
			CASE MODEL_IN1608xi:
			CASE MODEL_IN1804:
			CASE MODEL_IN1804DI:
			CASE MODEL_IN1804DO:
			CASE MODEL_IN1806:
			CASE MODEL_IN1808:
			CASE MODEL_MPS601:
			CASE MODEL_MPS602:{
				fnAddToQueue("$1B,'0LS',$0D",TRUE)//***Note: This may need to be 'OLS' for 1804 Series Scalers, unless it is just a typo in the manual!
			}
			CASE MODEL_SW2HD4k:
			CASE MODEL_SW2HD4kPlus:
			CASE MODEL_SW4HD4k:
			CASE MODEL_SW4HD4kPlus:
			CASE MODEL_SW4HD4kDTP:
			CASE MODEL_SW6:
			CASE MODEL_SW6HD4k:
			CASE MODEL_SW6HD4kPlus:
			CASE MODEL_SW8:
			CASE MODEL_SW8HD4k:
			CASE MODEL_SW8HD4kPlus:{
				fnAddToQueue("$1B,'LS',$0D",TRUE)
			}
		}
	}
}
/******************************************************************************
	Device Events
******************************************************************************/
DEFINE_EVENT DATA_EVENT[dvDevice]{
	ONLINE:{
		mySwitch.IP_STATE	= IP_STATE_CONNECTED
		IF(!mySwitch.isIP){
		   SEND_COMMAND dvDevice, 'SET MODE DATA'
		   SEND_COMMAND dvDevice, 'SET BAUD 9600 N 8 1 485 DISABLE'
		   SEND_COMMAND dvDevice, 'SET FAULT DETECT OFF'
		}
		WAIT 10{
			fnPollFull()
			fnInitPoll()
		}
	}
	OFFLINE:{
		IF(mySwitch.isIP){
			mySwitch.IP_STATE	= IP_STATE_OFFLINE
			fnRetryConnection()
		}
	}
	ONERROR:{
		IF(mySwitch.isIP){
			STACK_VAR CHAR _MSG[255]
			SWITCH(DATA.NUMBER){
				CASE 14:_MSG = 'Local Port Already Used'	// Local Port Already Used
				DEFAULT:{
					mySwitch.IP_STATE = IP_STATE_OFFLINE
					SWITCH(DATA.NUMBER){
						CASE 2:{ _MSG = 'General Failure'}					// General Failure - Out Of Memory
						CASE 4:{ _MSG = 'Unknown Host'}						// Unknown Host
						CASE 6:{ _MSG = 'Conn Refused'}						// Connection Refused
						CASE 7:{ _MSG = 'Conn Timed Out'}					// Connection Timed Out
						CASE 8:{ _MSG = 'Unknown'}								// Unknown Connection Error
						CASE 9:{ _MSG = 'Already Closed'}					// Already Closed
						CASE 10:{_MSG = 'Binding Error'} 					// Binding Error
						CASE 11:{_MSG = 'Listening Error'} 					// Listening Error
						CASE 15:{_MSG = 'UDP Socket Already Listening'} // UDP socket already listening
						CASE 16:{_MSG = 'Too many open Sockets'}			// Too many open sockets
						CASE 17:{_MSG = 'Local port not Open'}				// Local Port Not Open
					}
					fnRetryConnection()
				}
			}
			fnDebug(TRUE,"'Extron IP Error:[',mySwitch.IP_HOST,']'","'[',ITOA(DATA.NUMBER),'][',_MSG,']'")
		}
	}
	STRING:{
		IF(!mySwitch.DISABLED){
			fnDebug(FALSE,'Extron->AMX', DATA.TEXT);
			SELECT{
				ACTIVE(DATA.TEXT == "$0D,$0A,'Password:'"):{
					SEND_STRING dvDevice,"mySwitch.PASSWORD,$0D"
				}
				ACTIVE(mySwitch.LAST_SENT == 'N'):{
					STACK_VAR CHAR PartNo[30]

					PartNo = fnStripCharsRight(DATA.TEXT,2)
					IF(LEFT_STRING(PartNo,3) == 'Pno'){
						GET_BUFFER_STRING(PartNo,3)
					}
					IF(mySwitch.META_PART_NUMBER != Partno){
						mySwitch.META_PART_NUMBER = Partno
						SEND_STRING vdvControl,"'PROPERTY-META,PART,',mySwitch.META_PART_NUMBER"
						fnResetModule()
						fnPollFull()
					}
					ELSE IF(mySwitch.MODEL_ID == MODEL_NA){
						SWITCH(mySwitch.META_PART_NUMBER){
							CASE '60-1457-01':													// IN1604
							CASE '60-1457-02':mySwitch.MODEL_ID = MODEL_IN1604			// IN1604
							CASE '60-1081-01':mySwitch.MODEL_ID = MODEL_IN1606			// IN1606
							CASE '60-1238-51':													// IN1608
							CASE '60-1238-71':mySwitch.MODEL_ID = MODEL_IN1608			// IN1608
							CASE '60-1238-81':mySwitch.MODEL_ID = MODEL_IN1608xi		// IN1608xi
							CASE '60-1699-01':mySwitch.MODEL_ID = MODEL_IN1804			// IN1804
							CASE '60-1699-02':mySwitch.MODEL_ID = MODEL_IN1804DI		// IN1804DTP-IN
							CASE '60-1699-03':mySwitch.MODEL_ID = MODEL_IN1804DO		// IN1804DTP-OUT
							CASE '60-1663-01':mySwitch.MODEL_ID = MODEL_IN1806			// IN1806
							CASE '60-1615-01':mySwitch.MODEL_ID = MODEL_IN1808			// IN1808
							CASE '60-1377-01':mySwitch.MODEL_ID = MODEL_MPS601			// MPS601
							CASE '60-1313-01':mySwitch.MODEL_ID = MODEL_MPS602			// MPS602
							CASE '60-952-02': mySwitch.MODEL_ID = MODEL_SW2USB			// SW2USB
							CASE '60-1483-01':mySwitch.MODEL_ID = MODEL_SW2HD4k		// SW2HD4k
							CASE '60-1603-01':mySwitch.MODEL_ID = MODEL_SW2HD4kPlus	// SW2HD4kPlus
							CASE '60-1484-01':mySwitch.MODEL_ID = MODEL_SW4HD4k		// SW4HD4k
							CASE '60-1604-01':mySwitch.MODEL_ID = MODEL_SW4HD4kPlus	// SW4HD4kPlus
							CASE '60-1625-01':mySwitch.MODEL_ID = MODEL_SW4HD4kDTP	// SW4HD4kDTP-T
							CASE '60-841-03': mySwitch.MODEL_ID = MODEL_SW6				// SW6
							CASE '60-1485-01':mySwitch.MODEL_ID = MODEL_SW6HD4k		// SW6HD4k
							CASE '60-1605-01':mySwitch.MODEL_ID = MODEL_SW6HD4kPlus	// SW6HD4k Plus
							CASE '60-841-04': mySwitch.MODEL_ID = MODEL_SW8				// SW8
							CASE '60-1486-01':mySwitch.MODEL_ID = MODEL_SW8HD4k		// SW8HD4k
							CASE '60-1606-01':mySwitch.MODEL_ID = MODEL_SW8HD4kPlus	// SW8HD4k Plus
							CASE '60-1090-01':mySwitch.MODEL_ID = MODEL_MLAVC10		// MLA-VC10
							CASE '60-1551-12':mySwitch.MODEL_ID = MODEL_DTPTUSW233	// DTP-T USW 233
							CASE '60-1551-52':mySwitch.MODEL_ID = MODEL_DTPTUSW333	// DTP-T USW 333
						}
						SWITCH(mySwitch.MODEL_ID){
							CASE MODEL_DTPTUSW233:	mySwitch.META_MODEL = 'DTP-T USW 233'
							CASE MODEL_DTPTUSW333:	mySwitch.META_MODEL = 'DTP-T USW 333'
							CASE MODEL_IN1604:		mySwitch.META_MODEL = 'IN1604'
							CASE MODEL_IN1606:		mySwitch.META_MODEL = 'IN1606'
							CASE MODEL_IN1608:		mySwitch.META_MODEL = 'IN1608'
							CASE MODEL_IN1608xi:		mySwitch.META_MODEL = 'IN1608xi'
							CASE MODEL_IN1804:		mySwitch.META_MODEL = 'IN1804'
							CASE MODEL_IN1804DI:		mySwitch.META_MODEL = 'IN1804DI'
							CASE MODEL_IN1804DO:		mySwitch.META_MODEL = 'IN1804DO'
							CASE MODEL_IN1806:		mySwitch.META_MODEL = 'IN1806'
							CASE MODEL_IN1808:		mySwitch.META_MODEL = 'IN1808'
							CASE MODEL_MPS601:		mySwitch.META_MODEL = 'MPS601'
							CASE MODEL_MPS602:		mySwitch.META_MODEL = 'MPS602'
							CASE MODEL_SW2USB:		mySwitch.META_MODEL = 'SW2USB'
							CASE MODEL_SW2HD4k:		mySwitch.META_MODEL = 'SW2HD4k'
							CASE MODEL_SW2HD4kPlus:	mySwitch.META_MODEL = 'SW2HD4kPlus'
							CASE MODEL_SW4HD4k:		mySwitch.META_MODEL = 'SW4HD4k'
							CASE MODEL_SW4HD4kPlus:	mySwitch.META_MODEL = 'SW4HD4kPlus'
							CASE MODEL_SW4HD4kDTP:	mySwitch.META_MODEL = 'SW4HD4kDTP'
							CASE MODEL_SW6:			mySwitch.META_MODEL = 'SW6'
							CASE MODEL_SW6HD4k:		mySwitch.META_MODEL = 'SW6HD4k'
							CASE MODEL_SW6HD4kPlus:	mySwitch.META_MODEL = 'SW6HD4kPlus'
							CASE MODEL_SW8:			mySwitch.META_MODEL = 'SW8'
							CASE MODEL_SW8HD4k:		mySwitch.META_MODEL = 'SW8HD4k'
							CASE MODEL_SW8HD4kPlus:	mySwitch.META_MODEL = 'SW8HD4kPlus'
							CASE MODEL_MLAVC10:		mySwitch.META_MODEL = 'MLA-VC10'
							DEFAULT:						mySwitch.META_MODEL = 'NOT IMPLEMENTED'
						}
						SWITCH(mySwitch.MODEL_ID){
							CASE MODEL_SW2HD4kPlus:
							CASE MODEL_SW4HD4kPlus:
							CASE MODEL_SW6HD4kPlus:
							CASE MODEL_SW8HD4kPlus:
							CASE MODEL_IN1804:
							CASE MODEL_IN1804DI:
							CASE MODEL_IN1804DO:
							CASE MODEL_IN1806:
							CASE MODEL_IN1808:
							CASE MODEL_IN1606:
							CASE MODEL_IN1608:
							CASE MODEL_IN1608xi: mySwitch.HAS_NETWORK = TRUE
							DEFAULT:				   mySwitch.HAS_NETWORK = FALSE
						}
						SWITCH(mySwitch.MODEL_ID){
							CASE MODEL_MLAVC10:
							CASE MODEL_IN1604:
							CASE MODEL_IN1606:
							CASE MODEL_IN1608:
							CASE MODEL_IN1608xi:
							CASE MODEL_IN1804:
							CASE MODEL_IN1804DI:
							CASE MODEL_IN1804DO:
							CASE MODEL_IN1806:
							CASE MODEL_IN1808:{
								mySwitch.HAS_AUDIO 	= TRUE
								SEND_STRING vdvControl, 'RANGE-0,100'
							}
							DEFAULT:				mySwitch.HAS_AUDIO 	= FALSE
						}
						SEND_STRING vdvControl,"'PROPERTY-META,TYPE,VideoSwitch'"
						SEND_STRING vdvControl,"'PROPERTY-META,MAKE,Extron'"
						SEND_STRING vdvControl,"'PROPERTY-META,MODEL,',mySwitch.META_MODEL"
						IF(!mySwitch.HAS_NETWORK){
							SEND_STRING vdvControl,"'PROPERTY-META,NET_MAC,N/A'"
							SEND_STRING vdvControl,"'PROPERTY-STATE,NET_IP,N/A'"
						}
						ELSE{
							IF(mySwitch.HAS_NETWORK){
								IF(!LENGTH_ARRAY(mySwitch.META_MAC)){
									fnAddToQueue("$1B,'CH',$0D",TRUE)
								}
								fnAddToQueue("$1B,'CI',$0D",TRUE)
							}
						}
					}
				}
				ACTIVE(mySwitch.LAST_SENT == 'V'):{
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_MLAVC10:	mySwitch.AUDIO[AUDIO_PRO].GAIN = ATOI(DATA.TEXT)
						DEFAULT:					mySwitch.AUDIO[AUDIO_PRO].GAIN = ATOI(DATA.TEXT) + 100
					}
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'D1GRPM',$0D"):{
					mySwitch.AUDIO[AUDIO_PRO].GAIN = (ATOI(DATA.TEXT) + 1000) / 10
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'D3GRPM',$0D"):{
					mySwitch.AUDIO[AUDIO_MIC].GAIN = (ATOI(DATA.TEXT) + 1000) / 10
				}
				ACTIVE(mySwitch.LAST_SENT == 'Z'):{
					mySwitch.AUDIO[AUDIO_PRO].MUTE = ATOI("DATA.TEXT[1]")
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'D2GRPM',$0D"):{
					mySwitch.AUDIO[AUDIO_PRO].MUTE = ATOI("DATA.TEXT[1]")
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'D4GRPM',$0D"):{
					mySwitch.AUDIO[AUDIO_MIC].MUTE = ATOI("DATA.TEXT[1]")
				}
				ACTIVE(mySwitch.LAST_SENT == 'Q'):{
					mySwitch.META_FIRMWARE = fnStripCharsRight(DATA.TEXT,2)
					IF(LEFT_STRING(mySwitch.META_FIRMWARE,3) == 'Ver'){
						GET_BUFFER_STRING(mySwitch.META_FIRMWARE,3)
					}
					SEND_STRING vdvControl,"'PROPERTY-META,FW1,',fnRemoveNonPrintableChars(mySwitch.META_FIRMWARE)"
				}
				ACTIVE(mySwitch.LAST_SENT == '*Q'):{
					mySwitch.META_FIRMWARE_FULL = fnStripCharsRight(DATA.TEXT,2)
					IF(LEFT_STRING(mySwitch.META_FIRMWARE_FULL,3) == 'Bld'){
						GET_BUFFER_STRING(mySwitch.META_FIRMWARE_FULL,3)
					}
					IF(LEFT_STRING(mySwitch.META_FIRMWARE_FULL,6) == 'Ver*0 '){
						GET_BUFFER_STRING(mySwitch.META_FIRMWARE_FULL,6)
					}
					SEND_STRING vdvControl,"'PROPERTY-META,FW2,',fnRemoveNonPrintableChars(mySwitch.META_FIRMWARE_FULL)"
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'CH',$0D"):{
					mySwitch.META_MAC = fnStripCharsRight(DATA.TEXT,2)
					SEND_STRING vdvControl,"'PROPERTY-META,NET_MAC,',fnRemoveNonPrintableChars(mySwitch.META_MAC)"
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'CI',$0D"):{
					IF(mySwitch.META_IP != fnStripCharsRight(DATA.TEXT,2)){
						mySwitch.META_IP = fnStripCharsRight(DATA.TEXT,2)
						SEND_STRING vdvControl,"'PROPERTY-STATE,NET_IP,',fnRemoveNonPrintableChars(mySwitch.META_IP)"
					}
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'20STAT',$0D"):{
					IF(mySwitch.DIAG_INT_TEMP != fnStripCharsRight(DATA.TEXT,2)){
						mySwitch.DIAG_INT_TEMP = fnStripCharsRight(DATA.TEXT,2)
						SEND_STRING vdvControl,"'PROPERTY-STATE,TEMP,',mySwitch.DIAG_INT_TEMP"
					}
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'0LS',$0D"):{
					STACK_VAR INTEGER x
					IF(mySwitch.MODEL_ID == MODEL_IN1604){
						mySwitch.SIGNAL[1] = ATOI("DATA.TEXT[1]")
						mySwitch.SIGNAL[2] = ATOI("DATA.TEXT[2]")
						mySwitch.SIGNAL[3] = ATOI("DATA.TEXT[3]")
						mySwitch.SIGNAL[4] = ATOI("DATA.TEXT[4]")
					}
					ELSE{
						// Strip off possible leading
						IF(LEFT_STRING(DATA.TEXT,5) == 'In00 '){
							GET_BUFFER_STRING(DATA.TEXT,5)
						}
						WHILE(FIND_STRING(DATA.TEXT,'*',1)){
							x++
							mySwitch.SIGNAL[x] = ATOI(fnStripCharsRight(REMOVE_STRING(DATA.TEXT,'*',1),1))
						}
						x++
						mySwitch.SIGNAL[x] = ATOI(fnStripCharsRight(DATA.TEXT,2))
					}
				}
				ACTIVE(mySwitch.LAST_SENT == "$1B,'LS',$0D"):{
					STACK_VAR INTEGER x
					WHILE(FIND_STRING(DATA.TEXT,' ',1)){
						x++
						mySwitch.SIGNAL[x] = ATOI(fnStripCharsRight(REMOVE_STRING(DATA.TEXT,' ',1),1))
					}
					x++
					mySwitch.SIGNAL[x] = ATOI(fnStripCharsRight(REMOVE_STRING(DATA.TEXT,'*',1),1))
				}
				ACTIVE(1):{	// Referenced Notifications
					SELECT{
						ACTIVE(LEFT_STRING(DATA.TEXT,7) == 'GrpmD1*'):{
							GET_BUFFER_STRING(DATA.TEXT,7)
							mySwitch.AUDIO[AUDIO_PRO].GAIN = (ATOI(DATA.TEXT) + 1000) / 10
						}
						ACTIVE(LEFT_STRING(DATA.TEXT,7) == 'GrpmD3*'):{
							GET_BUFFER_STRING(DATA.TEXT,7)
							mySwitch.AUDIO[AUDIO_MIC].GAIN = (ATOI(DATA.TEXT) + 1000) / 10
						}
						ACTIVE(LEFT_STRING(DATA.TEXT,3) == 'Vol'):{
							GET_BUFFER_STRING(DATA.TEXT,3)
							SWITCH(mySwitch.MODEL_ID){
								CASE MODEL_MLAVC10:	mySwitch.AUDIO[AUDIO_PRO].GAIN = ATOI(DATA.TEXT)
								DEFAULT:					mySwitch.AUDIO[AUDIO_PRO].GAIN = ATOI(DATA.TEXT) + 100
							}
						}
						ACTIVE(LEFT_STRING(DATA.TEXT,3) == 'Amt'):{
							GET_BUFFER_STRING(DATA.TEXT,3)
							mySwitch.AUDIO[AUDIO_PRO].MUTE = ATOI(DATA.TEXT)
						}
					}
				}
			}
			mySwitch.LAST_SENT = ''
			IF(TIMELINE_ACTIVE(TLID_SEND)){TIMELINE_KILL(TLID_SEND)}
			fnSendFromQueue()
			IF(TIMELINE_ACTIVE(TLID_COMMS)){ TIMELINE_KILL(TLID_COMMS) }
			TIMELINE_CREATE(TLID_COMMS,TLT_COMMS,LENGTH_ARRAY(TLT_COMMS),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
		}
	}
}

DEFINE_EVENT TIMELINE_EVENT[TLID_COMMS]{
	mySwitch.META_PART_NUMBER	= ''
	fnResetModule()
}

DEFINE_FUNCTION fnResetModule(){
	STACK_VAR uGain blankGain
	mySwitch.Tx 					= ''
	mySwitch.LAST_SENT			= ''
	mySwitch.DIAG_INT_TEMP 		= ''
	mySwitch.AUDIO[AUDIO_PRO]  = blankGain
	mySwitch.AUDIO[AUDIO_MIC]  = blankGain
	mySwitch.HAS_AUDIO 			= FALSE
	mySwitch.HAS_NETWORK 		= FALSE
	mySwitch.META_FIRMWARE		= ''
	mySwitch.META_FIRMWARE_FULL= ''
	mySwitch.META_IP				= ''
	mySwitch.META_MAC				= ''
	mySwitch.META_MODEL			= ''
	mySwitch.MODEL_ID 			= 0
	mySwitch.SIGNAL[1]			= FALSE
	mySwitch.SIGNAL[2]			= FALSE
	mySwitch.SIGNAL[3]			= FALSE
	mySwitch.SIGNAL[4]			= FALSE
	mySwitch.SIGNAL[5]			= FALSE
	mySwitch.SIGNAL[6]			= FALSE
	mySwitch.SIGNAL[7]			= FALSE
	mySwitch.SIGNAL[8]			= FALSE
}

/******************************************************************************
	Control Events
******************************************************************************/
DEFINE_EVENT DATA_EVENT[vdvControl]{
	ONLINE:{
		IF(!mySwitch.DISABLED){
		}
	}
	COMMAND:{
		// Enable / Disable Module
		SWITCH(DATA.TEXT){
			CASE 'PROPERTY-ENABLED,FALSE':mySwitch.DISABLED = TRUE
			CASE 'PROPERTY-ENABLED,TRUE': mySwitch.DISABLED = FALSE
		}
		IF(!mySwitch.DISABLED){
			SWITCH(fnStripCharsRight(REMOVE_STRING(DATA.TEXT,'-',1),1)){
				CASE 'PROPERTY':{
					SWITCH(fnStripCharsRight(REMOVE_STRING(DATA.TEXT,',',1),1)){
						CASE 'DEBUG': 		mySwitch.DEBUG 	= (ATOI(DATA.TEXT) || DATA.TEXT == 'TRUE');
						CASE 'POLL':		mySwitch.NOPOLL 	= (DATA.TEXT == 'FALSE')
						CASE 'PASSWORD':  mySwitch.PASSWORD = DATA.TEXT
						CASE 'IP':{
							IF(FIND_STRING(DATA.TEXT,':',1)){
								mySwitch.IP_HOST = fnStripCharsRight(REMOVE_STRING(DATA.TEXT,':',1),1)
								mySwitch.IP_PORT = ATOI(DATA.TEXT)
							}
							ELSE{
								mySwitch.IP_HOST = DATA.TEXT
								mySwitch.IP_PORT = 23
							}
							IF(mySwitch.isIP){
								fnRetryConnection()
							}
						}
					}
				}
				CASE 'INPUT':{
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_IN1806:
						CASE MODEL_IN1808:{
							SWITCH(DATA.TEXT){
								CASE '0':{
									fnAddToQueue("'1B'",FALSE)						// Video Mute
									fnAddToQueue("$1B,'D10*1GRPM',$0D",FALSE)	//Master Audio Mute
								}
								DEFAULT:{
									fnAddToQueue("'0B'",FALSE)						// Video Unmute
									fnAddToQueue("$1B,'D10*0GRPM',$0D",FALSE)	// Master Audio Unmute
									fnAddToQueue("DATA.TEXT,'*1!'",FALSE)
								}
							}
						}
						DEFAULT:{
							fnAddToQueue("DATA.TEXT,'!'",FALSE)
						}
					}
				}
				CASE 'AINPUT':{
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_IN1804:
						CASE MODEL_IN1804DI:
						CASE MODEL_IN1804DO:	send_string 0, 'seperate audio switching not supported'
						CASE MODEL_IN1806:
						CASE MODEL_IN1808:	fnAddToQueue("DATA.TEXT,'*1$'",FALSE)
						DEFAULT:					fnAddToQueue("DATA.TEXT,'$'",FALSE)
					}
				}
				CASE 'VINPUT':{
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_IN1804:
						CASE MODEL_IN1804DI:
						CASE MODEL_IN1804DO:	send_string 0, 'seperate video switching not supported'
						CASE MODEL_IN1806:
						CASE MODEL_IN1808:	fnAddToQueue("DATA.TEXT,'*1%'",FALSE)
						DEFAULT:					fnAddToQueue("DATA.TEXT,'&'",FALSE)
					}
				}
				CASE 'VOLUME':{
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_MLAVC10:
						CASE MODEL_IN1604:
						CASE MODEL_IN1804:
						CASE MODEL_IN1804DI:
						CASE MODEL_IN1804DO:{
							SWITCH(DATA.TEXT){
								CASE 'INC':	fnAddToQueue('+V',FALSE)
								CASE 'DEC':	fnAddToQueue('-V',FALSE)
								DEFAULT:{
									SINTEGER VOL
									VOL = -100
									VOL = VOL + ATOI(DATA.TEXT)
									IF(!TIMELINE_ACTIVE(TLID_GAIN_00+AUDIO_PRO)){
										fnAddToQueue("ITOA(VOL),'V'",FALSE)
										TIMELINE_CREATE(TLID_GAIN_00+AUDIO_PRO,TLT_GAIN,LENGTH_ARRAY(TLT_GAIN),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
									}
									ELSE{
										mySwitch.AUDIO[AUDIO_PRO].LAST_GAIN = VOL
										mySwitch.AUDIO[AUDIO_PRO].GAIN_PEND = TRUE
									}
								}
							}
						}
						CASE MODEL_IN1606:
						CASE MODEL_IN1608:
						CASE MODEL_IN1608xi:{
							SWITCH(DATA.TEXT){
								CASE 'INC':	fnAddToQueue("$1B,'D1*20+GRPM',$0D",FALSE)
								CASE 'DEC':	fnAddToQueue("$1B,'D1*20-GRPM',$0D",FALSE)
								DEFAULT:{
									SINTEGER VOL
									VOL = -1000
									VOL = VOL + (ATOI(DATA.TEXT) * 10)
									IF(!TIMELINE_ACTIVE(TLID_GAIN_00+AUDIO_PRO)){
										fnAddToQueue("$1B,'D1*',ITOA(VOL),'GRPM',$0D",FALSE)
										TIMELINE_CREATE(TLID_GAIN_00+AUDIO_PRO,TLT_GAIN,LENGTH_ARRAY(TLT_GAIN),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
									}
									ELSE{
										mySwitch.AUDIO[AUDIO_PRO].LAST_GAIN = VOL
										mySwitch.AUDIO[AUDIO_PRO].GAIN_PEND = TRUE
									}
								}
							}
						}
						CASE MODEL_IN1806:
						CASE MODEL_IN1808:{
							SWITCH(DATA.TEXT){
								CASE 'INC':	fnAddToQueue("$1B,'D3*20+GRPM',$0D",FALSE)
								CASE 'DEC':	fnAddToQueue("$1B,'D3*20-GRPM',$0D",FALSE)
								DEFAULT:{
									SINTEGER VOL
									VOL = -1000
									VOL = VOL + (ATOI(DATA.TEXT) * 10)
									IF(!TIMELINE_ACTIVE(TLID_GAIN_00+AUDIO_PRO)){
										fnAddToQueue("$1B,'D3*',ITOA(VOL),'GRPM',$0D",FALSE)
										TIMELINE_CREATE(TLID_GAIN_00+AUDIO_PRO,TLT_GAIN,LENGTH_ARRAY(TLT_GAIN),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
									}
									ELSE{
										mySwitch.AUDIO[AUDIO_PRO].LAST_GAIN = VOL
										mySwitch.AUDIO[AUDIO_PRO].GAIN_PEND = TRUE
									}
								}
							}
						}
					}
				}
				CASE 'MICVOLUME':{
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_IN1606:
						CASE MODEL_IN1608:
						CASE MODEL_IN1608xi:{
							SWITCH(DATA.TEXT){
								CASE 'INC':	fnAddToQueue("$1B,'D3*20+GRPM',$0D",FALSE)
								CASE 'DEC':	fnAddToQueue("$1B,'D3*20-GRPM',$0D",FALSE)
								DEFAULT:{
									SINTEGER VOL
									VOL = -1000
									VOL = VOL + (ATOI(DATA.TEXT) * 10)
									IF(!TIMELINE_ACTIVE(TLID_GAIN_00+AUDIO_MIC)){
										fnAddToQueue("$1B,'D3*',ITOA(VOL),'GRPM',$0D",FALSE)
										TIMELINE_CREATE(TLID_GAIN_00+AUDIO_MIC,TLT_GAIN,LENGTH_ARRAY(TLT_GAIN),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
									}
									ELSE{
										mySwitch.AUDIO[AUDIO_MIC].LAST_GAIN = VOL
										mySwitch.AUDIO[AUDIO_MIC].GAIN_PEND = TRUE
									}
								}
							}
						}
					}
				}
				CASE 'MUTE':{
					SWITCH(DATA.TEXT){
						CASE 'ON':		mySwitch.AUDIO[AUDIO_PRO].MUTE = TRUE
						CASE 'OFF':		mySwitch.AUDIO[AUDIO_PRO].MUTE = FALSE
						CASE 'TOGGLE':	mySwitch.AUDIO[AUDIO_PRO].MUTE = !mySwitch.AUDIO[AUDIO_PRO].MUTE
					}
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_MLAVC10:
						CASE MODEL_IN1604:
						CASE MODEL_IN1804:
						CASE MODEL_IN1804DI:
						CASE MODEL_IN1804DO: fnAddToQueue("ITOA(mySwitch.AUDIO[AUDIO_PRO].MUTE),'Z'",FALSE)
						CASE MODEL_IN1806:
						CASE MODEL_IN1808:	fnAddToQueue("$1B,'D4*',ITOA(mySwitch.AUDIO[AUDIO_PRO].MUTE),'GRPM',$0D",FALSE)
						CASE MODEL_IN1606:
						CASE MODEL_IN1608:
						CASE MODEL_IN1608xi: fnAddToQueue("$1B,'D2*',ITOA(mySwitch.AUDIO[AUDIO_PRO].MUTE),'GRPM',$0D",FALSE)
					}
				}
				CASE 'MICMUTE':{
					SWITCH(DATA.TEXT){
						CASE 'ON':		mySwitch.AUDIO[AUDIO_MIC].MUTE = TRUE
						CASE 'OFF':		mySwitch.AUDIO[AUDIO_MIC].MUTE = FALSE
						CASE 'TOGGLE':	mySwitch.AUDIO[AUDIO_MIC].MUTE = !mySwitch.AUDIO[AUDIO_MIC].MUTE
					}
					SWITCH(mySwitch.MODEL_ID){
						CASE MODEL_IN1606:
						CASE MODEL_IN1608:
						CASE MODEL_IN1608xi: fnAddToQueue("$1B,'D4*',ITOA(mySwitch.AUDIO[AUDIO_MIC].MUTE),'GRPM',$0D",FALSE)
					}
				}
				CASE 'RAW':{
					fnAddToQueue(DATA.TEXT,FALSE)
				}
				CASE 'OUTPUT_RESOLUTION':{
					fnAddToQueue("$1B,DATA.TEXT,'RATE',$0D",FALSE)
				}
			}
		}
	}
}
DEFINE_EVENT CHANNEL_EVENT[vdvControl,199]{
	ON:{}
	OFF:{}
}
DEFINE_EVENT TIMELINE_EVENT[TLID_GAIN_01]{
	IF(mySwitch.AUDIO[AUDIO_PRO].GAIN_PEND){
		SWITCH(mySwitch.MODEL_ID){
			CASE MODEL_IN1604:
			CASE MODEL_IN1804:   fnAddToQueue("ITOA(mySwitch.AUDIO[AUDIO_PRO].LAST_GAIN),'V'",FALSE)
			CASE MODEL_IN1804DI:
			CASE MODEL_IN1804DO:
			CASE MODEL_IN1806:
			CASE MODEL_IN1808:   fnAddToQueue("$1B,'D3*',ITOA(mySwitch.AUDIO[AUDIO_PRO].LAST_GAIN),'GRPM',$0D",FALSE)
			CASE MODEL_IN1606:
			CASE MODEL_IN1608:
			CASE MODEL_IN1608xi: fnAddToQueue("$1B,'D1*',ITOA(mySwitch.AUDIO[AUDIO_PRO].LAST_GAIN),'GRPM',$0D",FALSE)
		}
		mySwitch.AUDIO[AUDIO_PRO].LAST_GAIN = 0
		mySwitch.AUDIO[AUDIO_PRO].GAIN_PEND = FALSE
		TIMELINE_CREATE(TLID_GAIN_01,TLT_GAIN,LENGTH_ARRAY(TLT_GAIN),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
	}
}
DEFINE_EVENT TIMELINE_EVENT[TLID_GAIN_02]{
	IF(mySwitch.AUDIO[AUDIO_MIC].GAIN_PEND){
		SWITCH(mySwitch.MODEL_ID){
			CASE MODEL_IN1606:
			CASE MODEL_IN1608:
			CASE MODEL_IN1608xi: fnAddToQueue("$1B,'D3*',ITOA(mySwitch.AUDIO[AUDIO_MIC].LAST_GAIN),'GRPM',$0D",FALSE)
		}
		mySwitch.AUDIO[AUDIO_MIC].LAST_GAIN = 0
		mySwitch.AUDIO[AUDIO_MIC].GAIN_PEND = FALSE
		TIMELINE_CREATE(TLID_GAIN_02,TLT_GAIN,LENGTH_ARRAY(TLT_GAIN),TIMELINE_ABSOLUTE,TIMELINE_ONCE)
	}
}
DEFINE_PROGRAM{
	IF(!mySwitch.DISABLED){
		[vdvControl,199] = (mySwitch.AUDIO[AUDIO_PRO].MUTE)
		[vdvControl,198] = (mySwitch.AUDIO[AUDIO_MIC].MUTE)
		SEND_LEVEL vdvControl,1,mySwitch.AUDIO[AUDIO_PRO].GAIN
		SEND_LEVEL vdvControl,2,mySwitch.AUDIO[AUDIO_MIC].GAIN
		[vdvControl,251] = (TIMELINE_ACTIVE(TLID_COMMS))
		[vdvControl,252] = (TIMELINE_ACTIVE(TLID_COMMS))
		[vdvControl,1] = (mySwitch.SIGNAL[1])
		[vdvControl,2] = (mySwitch.SIGNAL[2])
		[vdvControl,3] = (mySwitch.SIGNAL[3])
		[vdvControl,4] = (mySwitch.SIGNAL[4])
		[vdvControl,5] = (mySwitch.SIGNAL[5])
		[vdvControl,6] = (mySwitch.SIGNAL[6])
		[vdvControl,7] = (mySwitch.SIGNAL[7])
		[vdvControl,8] = (mySwitch.SIGNAL[8])
	}
}
/******************************************************************************
	EoF
******************************************************************************/