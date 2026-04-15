            XDEF  Entry, _Startup      ; export Entry symbol
            ABSENTRY Entry             ; for absolute assembly: mark entry
            INCLUDE "derivative.inc"

;***************************************************************************************************
; equates section
;***************************************************************************************************

; Liquid Crystal Display Equates
;-------------------------------
CLEAR_HOME      EQU   $01              ; Clear the display and home the cursor
INTERFACE       EQU   $38              ; 8 bit interface, two line display
CURSOR_OFF      EQU   $0C              ; Display on, cursor off
SHIFT_OFF       EQU   $06              ; Address increments, no character shift
LCD_SEC_LINE    EQU   64               ; Starting addr. of 2nd line of LCD (decimal)

; LCD Addresses
; -------------
LCD_CNTR        EQU   PTJ              ; LCD Control Register: E = PJ7, RS = PJ6
LCD_DAT         EQU   PORTB            ; LCD Data Register: D7 = PB7, ... , D0 = PB0
LCD_E           EQU   $80              ; LCD E-signal pin
LCD_RS          EQU   $40              ; LCD RS-signal pin

; Other codes
; -----------
NULL            EQU   0                ; string null terminator
CR              EQU   $0D              ; Carriage Return
SPACE           EQU   ' '              ; space character

; States for robot
;-----------------
START           EQU   0
FWD             EQU   1
ALL_STOP        EQU   2
LEFT_TURN       EQU   3
RIGHT_TURN      EQU   4
REV_TURN        EQU   5
LEFT_ALIGN      EQU   6
RIGHT_ALIGN     EQU   7

; variable/data section
; ---------------------
            ORG   $3800

; Initial values based on the initial readings & variance
; -------------------------------------------------------
BASE_LINE           FCB   $7F
BASE_BOW            FCB   $DF
BASE_MID            FCB   $C0
BASE_PORT           FCB   $C2
BASE_STBD           FCB   $CB

LINE_VARIANCE       FCB   $18          ; Adding variance based on testing to
BOW_VARIANCE        FCB   $30          ; establish baseline for sensors
PORT_VARIANCE       FCB   $20
MID_VARIANCE        FCB   $20
STARBOARD_VARIANCE  FCB   $15

TOP_LINE        RMB   20               ; Top line of display
                FCB   NULL             ; terminated by null
             
BOT_LINE        RMB   20               ; Bottom line of display
                FCB   NULL             ; terminated by null

CLEAR_LINE      FCC   '                  '  ; Clear the line of display
                FCB   NULL                  ; terminated by null

TEMP            RMB   1                 ; Temporary location

; Storage Registers (9S12C32 RAM space: $3800 ... $3FFF)
; ------------------------------------------------------
SENSOR_LINE     FCB   $01               ; Storage for guider sensor readings
SENSOR_BOW      FCB   $23               ; Initialized to test values
SENSOR_PORT     FCB   $45
SENSOR_MID      FCB   $67
SENSOR_STBD     FCB   $89
SENSOR_NUM      RMB   1

; variable section
;***************************************************************************************************
            ORG   $3850                ; Where our TOF counter register lives
TOF_COUNTER     DC.B  0                ; The timer, incremented at 23Hz
CRNT_STATE      DC.B  2                ; Current state register
T_TURN          DS.B  1                ; time to stop turning
TEN_THOUS       DS.B  1                ; 10,000 digit
THOUSANDS       DS.B  1                ; 1,000 digit
HUNDREDS        DS.B  1                ; 100 digit
TENS            DS.B  1                ; 10 digit
UNITS           DS.B  1                ; 1 digit
NO_BLANK        DS.B  1                ; Used in leading zero blanking by BCD2ASC
HEX_TABLE       FCC   '0123456789ABCDEF'  ; Table for converting values
BCD_SPARE       RMB   2

; code section
;***************************************************************************************************
            ORG   $4000
Entry:
_Startup:
            LDS   #$4000               ; Initialize the stack pointer
            CLI                        ; Enable interrupts
            JSR   INIT                 ; Initialize ports
            JSR   openADC              ; Initialize the ATD
            JSR   initLCD              ; Initialize the LCD
            JSR   CLR_LCD_BUF          ; Write space characters to the LCD buffer
            BSET  DDRA,%00000011       ; STAR_DIR, PORT_DIR                        
            BSET  DDRT,%00110000       ; STAR_SPEED, PORT_SPEED                    
            JSR   initAD               ; Initialize ATD converter                  
            JSR   initLCD              ; Initialize the LCD                        
            JSR   clrLCD               ; Clear LCD & home cursor                  
            LDX   #msg1                ; Display msg1                              
            JSR   putsLCD              ; "Battery volt"                                
            LDAA  #$C0                 ; Move LCD cursor to the 2nd row          
            JSR   cmd2LCD              
            LDX   #msg2                ; Display msg2                              
            JSR   putsLCD              ; "State"
            JSR   ENABLE_TOF           ; Initialize TOF and enable timer

MAIN:       
            JSR   G_LEDS_ON            ; Enable the guider LEDs  
            JSR   READ_SENSORS         ; Read the 5 guider sensors
            JSR   G_LEDS_OFF           ; Disable the guider LEDs                  
            JSR   DISPLAY_SENSORS      
            LDAA  CRNT_STATE        
            JSR   DISPATCHER        
            BRA   MAIN              

; data section
;***************************************************************************************************
msg1        DC.B  "Battery volt ",0
msg2        DC.B  "State",0
tab         DC.B  "start  ",0
            DC.B  "fwd    ",0
            DC.B  "all_stp",0
            DC.B  "LeftTurn ",0
            DC.B  "RightTurn",0
            DC.B  "RevTrn ",0
            DC.B  "LeftTimed ",0    
            DC.B  "RTimed ",0  

; subroutine section
;***************************************************************************************************
; State dispatcher
DISPATCHER:      CMPA  #START                  ; START?
                 BNE   VERIFY_FORWARD
                 JSR   START_ST
                 RTS

VERIFY_FORWARD:  CMPA  #FWD                    ; FWD?
                 BNE   VERIFY_STOP
                 JSR   FWD_ST
                 RTS
                 
VERIFY_REV_TURN: CMPA  #REV_TURN               ; REV_TURN?
                 BNE   VERIFY_LEFT_ALIGN
                 JSR   REV_TURN_ST
                 RTS

VERIFY_STOP:     CMPA  #ALL_STOP               ; ALL_STOP?
                 BNE   VERIFY_LEFT_TURN
                 JSR   ALL_STOP_ST
                 RTS

VERIFY_LEFT_TURN: CMPA #LEFT_TURN              ; LEFT_TURN?
                  BNE  VERIFY_RIGHT_TURN
                  JSR  LEFT
                  RTS                                                                                                                      

VERIFY_LEFT_ALIGN: CMPA #LEFT_ALIGN            ; LEFT_ALIGN?
                   BNE  VERIFY_RIGHT_ALIGN
                   JSR  LEFT_ALIGN_DONE
                   RTS

VERIFY_RIGHT_TURN: CMPA #RIGHT_TURN            ; RIGHT_TURN?
                   BNE  VERIFY_REV_TURN
                   JSR  RIGHT
                   RTS                                      

VERIFY_RIGHT_ALIGN: CMPA #RIGHT_ALIGN          ; RIGHT_ALIGN?
                    JSR  RIGHT_ALIGN_DONE
                    RTS

;***************************************************************************************************
; Movement / state routines
;***************************************************************************************************

; START: when front bumper is pressed
START_ST:        BRCLR PORTAD0, %00000100, RELEASE
                 JSR   INIT_FWD
                 MOVB  #FWD, CRNT_STATE
RELEASE:         RTS                                                                                                                                  

;***************************************************************************************************

; FORWARD state
FWD_ST:          BRSET PORTAD0, $04, NO_FWD_BUMP     ; Check bow bumper
                 MOVB  #REV_TURN, CRNT_STATE         ; if hit, go to REV_TURN
                 JSR   UPDT_DISPL
                 JSR   INIT_REV
                 LDY   #6000
                 JSR   del_50us
                 JSR   INIT_RIGHT
                 LDY   #6000
                 JSR   del_50us
                 LBRA  EXIT

NO_FWD_BUMP:     BRSET PORTAD0, $04, NO_FWD_REAR_BUMP ; (stern bumper - reused bit in template)
                 MOVB  #ALL_STOP, CRNT_STATE
                 JSR   INIT_STOP
                 LBRA  EXIT
                 
NO_FWD_REAR_BUMP:
                 LDAA  SENSOR_BOW
                 ADDA  BOW_VARIANCE
                 CMPA  BASE_BOW
                 BPL   NOT_ALIGNED

                 LDAA  SENSOR_MID
                 ADDA  MID_VARIANCE
                 CMPA  BASE_MID
                 BPL   NOT_ALIGNED

                 LDAA  SENSOR_LINE
                 ADDA  LINE_VARIANCE
                 CMPA  BASE_LINE
                 BPL   CHECK_RIGHT_ALIGN

                 LDAA  SENSOR_LINE
                 SUBA  LINE_VARIANCE
                 CMPA  BASE_LINE
                 BMI   CHECK_LEFT_ALIGN

;***************************************************************************************************                                                                  


NOT_ALIGNED:     LDAA  SENSOR_PORT
                 ADDA  PORT_VARIANCE
                 CMPA  BASE_PORT
                 BPL   PARTIAL_LEFT_TURN
                 BMI   NO_PORT

NO_PORT:         LDAA  SENSOR_BOW
                 ADDA  BOW_VARIANCE
                 CMPA  BASE_BOW
                 BPL   EXIT
                 BMI   NO_BOW

NO_BOW:          LDAA  SENSOR_STBD
                 ADDA  STARBOARD_VARIANCE
                 CMPA  BASE_STBD
                 BPL   PARTIAL_RIGHT_TURN
                 BMI   EXIT

;***************************************************************************************************

PARTIAL_LEFT_TURN:
                 LDY   #6000
                 JSR   del_50us
                 JSR   INIT_LEFT
                 MOVB  #LEFT_TURN, CRNT_STATE
                 LDY   #6000
                 JSR   del_50us
                 BRA   EXIT

CHECK_LEFT_ALIGN:
                 JSR   INIT_LEFT
                 MOVB  #LEFT_ALIGN, CRNT_STATE
                 BRA   EXIT

;***************************************************************************************************

PARTIAL_RIGHT_TURN:
                 LDY   #6000
                 JSR   del_50us
                 JSR   INIT_RIGHT
                 MOVB  #RIGHT_TURN, CRNT_STATE
                 LDY   #6000
                 JSR   del_50us
                 BRA   EXIT

CHECK_RIGHT_ALIGN:
                 JSR   INIT_RIGHT
                 MOVB  #RIGHT_ALIGN, CRNT_STATE
                 BRA   EXIT                                                                                                                                                        
                                                                                                
EXIT:            RTS

;***************************************************************************************************                                                                            


LEFT:            LDAA  SENSOR_BOW
                 ADDA  BOW_VARIANCE
                 CMPA  BASE_BOW
                 BPL   LEFT_ALIGN_DONE
                 BMI   EXIT

LEFT_ALIGN_DONE: MOVB  #FWD, CRNT_STATE
                 JSR   INIT_FWD
                 BRA   EXIT

RIGHT:           LDAA  SENSOR_BOW
                 ADDA  BOW_VARIANCE
                 CMPA  BASE_BOW
                 BPL   RIGHT_ALIGN_DONE
                 BMI   EXIT

RIGHT_ALIGN_DONE:
                 MOVB  #FWD, CRNT_STATE
                 JSR   INIT_FWD
                 BRA   EXIT

;***************************************************************************************************

REV_TURN_ST:     LDAA  SENSOR_BOW
                 ADDA  BOW_VARIANCE
                 CMPA  BASE_BOW
                 BMI   EXIT
                 JSR   INIT_LEFT
                 MOVB  #FWD, CRNT_STATE
                 JSR   INIT_FWD
                 BRA   EXIT

ALL_STOP_ST:     BRSET PORTAD0, %00000100, NO_START_BUMP
                 MOVB  #START, CRNT_STATE
NO_START_BUMP:   RTS


; Initialization Subroutines
;***************************************************************************************************
INIT_RIGHT:      BSET  PORTA,%00000010          
                 BCLR  PORTA,%00000001          
                 RTS

INIT_LEFT:       BSET  PORTA,%00000001        
                 BCLR  PORTA,%00000010             
                 RTS

INIT_FWD:        BCLR  PORTA,%00000011          ; Set FWD dir. for both motors
                 BSET  PTT,%00110000            ; Turn on the drive motors
                 RTS

INIT_REV:        BSET  PORTA,%00000011          ; Set REV direction for both motors
                 BSET  PTT,%00110000            ; Turn on the drive motors
                 RTS

INIT_STOP:       BCLR  PTT,%00110000            ; Turn off the drive motors
                 RTS


;***************************************************************************************************
;       Initialize Sensors / Ports
INIT:            BCLR   DDRAD,$FF       ; Make PORTAD an input (DDRAD @ $0272)
                 BSET   DDRA,$FF        ; Make PORTA an output (DDRA @ $0002)
                 BSET   DDRB,$FF        ; Make PORTB an output (DDRB @ $0003)
                 BSET   DDRJ,$C0        ; Make pins 7,6 of PTJ outputs (DDRJ @ $026A)
                 RTS


;***************************************************************************************************
;        Initialize ADC              
openADC:         MOVB   #$80,ATDCTL2    ; Turn on ADC (ATDCTL2 @ $0082)
                 LDY    #1              ; Wait for 50 us for ADC to be ready
                 JSR    del_50us
                 MOVB   #$20,ATDCTL3    ; 4 conversions on channel AN1 (ATDCTL3 @ $0083)
                 MOVB   #$97,ATDCTL4    ; 8-bit resolution, prescaler=48 (ATDCTL4 @ $0084)
                 RTS

;---------------------------------------------------------------------------
;                           Clear LCD Buffer
;---------------------------------------------------------------------------
CLR_LCD_BUF:     LDX   #CLEAR_LINE
                 LDY   #TOP_LINE
                 JSR   STRCPY

CLB_SECOND:      LDX   #CLEAR_LINE
                 LDY   #BOT_LINE
                 JSR   STRCPY

CLB_EXIT:        RTS

;---------------------------------------------------------------------------      
; String Copy
;---------------------------------------------------------------------------      
; X = src, Y = dest, copies until NULL (including NULL)
STRCPY:          PSHX
                 PSHY
                 PSHA

STRCPY_LOOP:     LDAA  0,X
                 STAA  0,Y
                 BEQ   STRCPY_EXIT
                 INX
                 INY
                 BRA   STRCPY_LOOP

STRCPY_EXIT:     PULA
                 PULY
                 PULX
                 RTS  

;---------------------------------------------------------------------------      
; Guider LEDs ON
;---------------------------------------------------------------------------      
G_LEDS_ON:       BSET  PORTA,%00100000   ; Set bit 5
                 RTS

;---------------------------------------------------------------------------      
; Guider LEDs OFF
;---------------------------------------------------------------------------      
G_LEDS_OFF:      BCLR  PORTA,%00100000   ; Clear bit 5
                 RTS    

;---------------------------------------------------------------------------      
; Read Sensors
;---------------------------------------------------------------------------
READ_SENSORS:    CLR   SENSOR_NUM        ; Select sensor number 0
                 LDX   #SENSOR_LINE      ; Point at the start of the sensor array

RS_MAIN_LOOP:    LDAA  SENSOR_NUM        ; Select the correct sensor input
                 JSR   SELECT_SENSOR
                 LDY   #400              ; 20 ms delay
                 JSR   del_50us
                 LDAA  #%10000001        ; Start A/D conversion on AN1
                 STAA  ATDCTL5
                 BRCLR ATDSTAT0,$80,*    ; Wait for done
                 LDAA  ATDDR0L           ; Result
                 STAA  0,X               ; Store
                 CPX   #SENSOR_STBD
                 BEQ   RS_EXIT
                 INC   SENSOR_NUM
                 INX
                 BRA   RS_MAIN_LOOP

RS_EXIT:         RTS


;---------------------------------------------------------------------------      
; Select Sensor
;---------------------------------------------------------------------------      
SELECT_SENSOR:   PSHA
                 LDAA  PORTA
                 ANDA  #%11100011        ; clear selection bits
                 STAA  TEMP
                 PULA
                 ASLA
                 ASLA
                 ANDA  #%00011100
                 ORAA  TEMP
                 STAA  PORTA
                 RTS


;---------------------------------------------------------------------------      
; Display Sensors
;---------------------------------------------------------------------------
DP_FRONT_SENSOR  EQU TOP_LINE+3
DP_PORT_SENSOR   EQU BOT_LINE+0
DP_MID_SENSOR    EQU BOT_LINE+3
DP_STBD_SENSOR   EQU BOT_LINE+6
DP_LINE_SENSOR   EQU BOT_LINE+9

DISPLAY_SENSORS: LDAA  SENSOR_BOW
                 JSR   BIN2ASC
                 LDX   #DP_FRONT_SENSOR
                 STD   0,X

                 LDAA  SENSOR_PORT
                 JSR   BIN2ASC
                 LDX   #DP_PORT_SENSOR
                 STD   0,X

                 LDAA  SENSOR_MID
                 JSR   BIN2ASC
                 LDX   #DP_MID_SENSOR
                 STD   0,X

                 LDAA  SENSOR_STBD
                 JSR   BIN2ASC
                 LDX   #DP_STBD_SENSOR
                 STD   0,X

                 LDAA  SENSOR_LINE
                 JSR   BIN2ASC
                 LDX   #DP_LINE_SENSOR
                 STD   0,X

                 LDAA  #CLEAR_HOME
                 JSR   cmd2LCD
                 LDY   #40               ; 2 ms
                 JSR   del_50us

                 LDX   #TOP_LINE
                 JSR   putsLCD

                 LDAA  #LCD_SEC_LINE
                 JSR   LCD_POS_CRSR

                 LDX   #BOT_LINE
                 JSR   putsLCD
                 RTS

;***************************************************************************************************
; Update Display (Battery Voltage + Current State)
;***************************************************************************************************
UPDT_DISPL:      MOVB  #$90,ATDCTL5      ; R-just., uns., single conv., mult., ch=0, start
                 BRCLR ATDSTAT0,$80,*    ; Wait for completion
                 LDAA  ATDDR0L           ; result
                 LDAB  #39
                 MUL                     ; D = result * 39
                 ADDD  #600              ; D = result*39 + 600
                 JSR   int2BCD
                 JSR   BCD2ASC

                 LDAA  #$8D              ; row 1, end of msg1
                 JSR   cmd2LCD

                 LDAA  TEN_THOUS
                 JSR   putcLCD
                 LDAA  THOUSANDS
                 JSR   putcLCD
                 LDAA  #'.'
                 JSR   putcLCD
                 LDAA  HUNDREDS
                 JSR   putcLCD

                 LDAA  #$C7              ; row 2, end of msg2
                 JSR   cmd2LCD
                 LDAB  CRNT_STATE
                 LSLB
                 LSLB
                 LSLB
                 LDX   #tab
                 ABX
                 JSR   putsLCD
                 RTS

;***************************************************************************************************
ENABLE_TOF:      LDAA  #%10000000
                 STAA  TSCR1             ; Enable TCNT
                 STAA  TFLG2             ; Clear TOF
                 LDAA  #%10000100        ; Enable TOI, prescaler /16
                 STAA  TSCR2
                 RTS

TOF_ISR:         INC   TOF_COUNTER
                 LDAA  #%10000000
                 STAA  TFLG2
                 RTI


; utility subroutines
;***************************************************************************************************
initLCD:         BSET  DDRB,%11111111    ; PORTB output
                 BSET  DDRJ,%11000000    ; PJ7, PJ6 output
                 LDY   #2000
                 JSR   del_50us
                 LDAA  #$28
                 JSR   cmd2LCD
                 LDAA  #$0C
                 JSR   cmd2LCD
                 LDAA  #$06
                 JSR   cmd2LCD
                 RTS

;***************************************************************************************************
clrLCD:          LDAA  #$01
                 JSR   cmd2LCD
                 LDY   #40
                 JSR   del_50us
                 RTS

;***************************************************************************************************
del_50us:        PSHX
eloop:           LDX   #300
iloop:           NOP
                 DBNE  X,iloop
                 DBNE  Y,eloop
                 PULX
                 RTS

;***************************************************************************************************
cmd2LCD:         BCLR  LCD_CNTR, LCD_RS ; instruction register
                 JSR   dataMov
                 RTS

;***************************************************************************************************
putsLCD:         LDAA  1,X+             ; get char
                 BEQ   donePS
                 JSR   putcLCD
                 BRA   putsLCD

donePS:          RTS

;***************************************************************************************************
putcLCD:         BSET  LCD_CNTR, LCD_RS ; data register
                 JSR   dataMov
                 RTS

;***************************************************************************************************
dataMov:         BSET  LCD_CNTR, LCD_E
                 STAA  LCD_DAT
                 BCLR  LCD_CNTR, LCD_E
                 LSLA
                 LSLA
                 LSLA
                 LSLA
                 BSET  LCD_CNTR, LCD_E
                 STAA  LCD_DAT
                 BCLR  LCD_CNTR, LCD_E
                 LDY   #1
                 JSR   del_50us
                 RTS

;***************************************************************************************************
initAD:          MOVB  #$C0,ATDCTL2      ; power up AD, fast flag clear
                 JSR   del_50us
                 MOVB  #$00,ATDCTL3      ; 8 conversions in sequence
                 MOVB  #$85,ATDCTL4      ; 8-bit, conv-clks=2, prescal=12
                 BSET  ATDDIEN,$0C       ; AN03, AN02 digital inputs
                 RTS

;***************************************************************************************************
int2BCD:         XGDX                    ; save binary in X
                 LDAA  #0
                 STAA  TEN_THOUS
                 STAA  THOUSANDS
                 STAA  HUNDREDS
                 STAA  TENS
                 STAA  UNITS
                 STAA  BCD_SPARE
                 STAA  BCD_SPARE+1
                 CPX   #0
                 BEQ   CON_EXIT
                 XGDX
                 LDX   #10
                 IDIV
                 STAB  UNITS
                 CPX   #0
                 BEQ   CON_EXIT
                 XGDX
                 LDX   #10
                 IDIV
                 STAB  TENS
                 CPX   #0
                 BEQ   CON_EXIT
                 XGDX
                 LDX   #10
                 IDIV
                 STAB  HUNDREDS
                 CPX   #0
                 BEQ   CON_EXIT
                 XGDX
                 LDX   #10
                 IDIV
                 STAB  THOUSANDS
                 CPX   #0
                 BEQ   CON_EXIT
                 XGDX
                 LDX   #10
                 IDIV
                 STAB  TEN_THOUS
CON_EXIT:        RTS

LCD_POS_CRSR:    ORAA  #%10000000
                 JSR   cmd2LCD
                 RTS

;***************************************************************************************************
BIN2ASC:         PSHA
                 TAB
                 ANDB #%00001111
                 CLRA
                 ADDD #HEX_TABLE
                 XGDX
                 LDAA 0,X               ; LSnibble char
                 PULB                   ; original number
                 PSHA                   ; push LSnibble char
                 RORB
                 RORB
                 RORB
                 RORB
                 ANDB #%00001111
                 CLRA
                 ADDD #HEX_TABLE
                 XGDX
                 LDAA 0,X               ; MSnibble char
                 PULB                   ; LSnibble char
                 RTS

;***************************************************************************************************
; BCD to ASCII
;***************************************************************************************************
BCD2ASC:         LDAA  #0
                 STAA  NO_BLANK

C_TTHOU:         LDAA  TEN_THOUS
                 ORAA  NO_BLANK
                 BNE   NOT_BLANK1

ISBLANK1:        LDAA  #' '
                 STAA  TEN_THOUS
                 BRA   C_THOU

NOT_BLANK1:      LDAA  TEN_THOUS
                 ORAA  #$30
                 STAA  TEN_THOUS
                 LDAA  #$1
                 STAA  NO_BLANK

C_THOU:          LDAA  THOUSANDS
                 ORAA  NO_BLANK
                 BNE   NOT_BLANK2

ISBLANK2:        LDAA  #' '
                 STAA  THOUSANDS
                 BRA   C_HUNS

NOT_BLANK2:      LDAA  THOUSANDS
                 ORAA  #$30
                 STAA  THOUSANDS
                 LDAA  #$1
                 STAA  NO_BLANK

C_HUNS:          LDAA  HUNDREDS
                 ORAA  NO_BLANK
                 BNE   NOT_BLANK3

ISBLANK3:        LDAA  #' '
                 STAA  HUNDREDS
                 BRA   C_TENS

NOT_BLANK3:      LDAA  HUNDREDS
                 ORAA  #$30
                 STAA  HUNDREDS
                 LDAA  #$1
                 STAA  NO_BLANK

C_TENS:          LDAA  TENS
                 ORAA  NO_BLANK
                 BNE   NOT_BLANK4

ISBLANK4:        LDAA  #' '
                 STAA  TENS
                 BRA   C_UNITS

NOT_BLANK4:      LDAA  TENS
                 ORAA  #$30
                 STAA  TENS

C_UNITS:         LDAA  UNITS
                 ORAA  #$30
                 STAA  UNITS
                 RTS

;***************************************************************************************************
; Interrupt Vectors
;***************************************************************************************************
            ORG   $FFFE
            DC.W  Entry      ; Reset Vector
            ORG   $FFDE
            DC.W  TOF_ISR    ; Timer Overflow Interrupt Vector
