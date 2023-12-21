' Original Author: Chip Gracey
' Modified with USB HID scancodes by Marco Maccaferri

VAR

  long  cog

  long  par_tail        'key buffer tail        read/write      (19 contiguous longs)
  long  par_head        'key buffer head        read-only
  long  par_present     'keyboard present       read-only
  long  par_states[8]   'key states (256 bits)  read-only
  long  par_keys[8]     'key buffer (16 words)  read-only       (also used to pass initial parameters)

PUB start(dpin, cpin) : okay

'' Start keyboard driver - starts a cog
'' returns false if no cog available
''
''   dpin  = data signal on PS/2 jack
''   cpin  = clock signal on PS/2 jack
''
''     use 100-ohm resistors between pins and jack
''     use 10K-ohm resistors to pull jack-side signals to VDD
''     connect jack-power to 5V, jack-gnd to VSS
''
'' all lock-keys will be enabled, NumLock will be initially 'on',
'' and auto-repeat will be set to 15cps with a delay of .5s

  okay := startx(dpin, cpin, %0_000_100, %01_10000)


PUB startx(dpin, cpin, locks, auto) : okay

'' Like start, but allows you to specify lock settings and auto-repeat
''
''   locks = lock setup
''           bit 6 disallows shift-alphas (case set soley by CapsLock)
''           bits 5..3 disallow toggle of NumLock/CapsLock/ScrollLock state
''           bits 2..0 specify initial state of NumLock/CapsLock/ScrollLock
''           (eg. %0_001_100 = disallow ScrollLock, NumLock initially 'on')
''
''   auto  = auto-repeat setup
''           bits 6..5 specify delay (0=.25s, 1=.5s, 2=.75s, 3=1s)
''           bits 4..0 specify repeat rate (0=30cps..31=2cps)
''           (eg %01_00000 = .5s delay, 30cps repeat)

  stop
  longmove(@par_keys, @dpin, 4)
  okay := cog := cognew(@entry, @par_tail) + 1


PUB stop

'' Stop keyboard driver - frees a cog

  if cog
    cogstop(cog~ -  1)
  longfill(@par_tail, 0, 19)


PUB present : truefalse

'' Check if keyboard present - valid ~2s after start
'' returns t|f

  truefalse := -par_present


PUB key : keycode

'' Get key (never waits)
'' returns key (0 if buffer empty)

  if par_tail <> par_head
    keycode := par_keys.word[par_tail]
    par_tail := ++par_tail & $F


PUB getkey : keycode

'' Get next key (may wait for keypress)
'' returns key

  repeat until (keycode := key)


PUB newkey : keycode

'' Clear buffer and get new key (always waits for keypress)
'' returns key

  par_tail := par_head
  keycode := getkey


PUB gotkey : truefalse

'' Check if any key in buffer
'' returns t|f

  truefalse := par_tail <> par_head


PUB clearkeys

'' Clear key buffer

  par_tail := par_head


PUB keystate(k) : state

'' Get the state of a particular key
'' returns t|f

  state := -(par_states[k >> 5] >> k & 1)


DAT

'******************************************
'* Assembly language PS/2 keyboard driver *
'******************************************

                        org
'
'
' Entry
'
entry                   movd    :par,#_dpin             'load input parameters _dpin/_cpin/_locks/_auto
                        mov     x,par
                        add     x,#11*4
                        mov     y,#4
:par                    rdlong  0,x
                        add     :par,dlsb
                        add     x,#4
                        djnz    y,#:par

                        mov     dmask,#1                'set pin masks
                        shl     dmask,_dpin
                        mov     cmask,#1
                        shl     cmask,_cpin

                        test    _dpin,#$20      wc      'modify port registers within code
                        muxc    _d1,dlsb
                        muxc    _d2,dlsb
                        muxc    _d3,#1
                        muxc    _d4,#1
                        test    _cpin,#$20      wc
                        muxc    _c1,dlsb
                        muxc    _c2,dlsb
                        muxc    _c3,#1

                        mov     _head,#0                'reset output parameter _head
'
'
' Reset keyboard
'
reset                   mov     dira,#0                 'reset directions
                        mov     dirb,#0

                        movd    :par,#_present          'reset output parameters _present/_states[8]
                        mov     x,#1+8
:par                    mov     0,#0
                        add     :par,dlsb
                        djnz    x,#:par

                        mov     stat,#8                 'set reset flag
'
'
' Update parameters
'
update                  movd    :par,#_head             'update output parameters _head/_present/_states[8]
                        mov     x,par
                        add     x,#1*4
                        mov     y,#1+1+8
:par                    wrlong  0,x
                        add     :par,dlsb
                        add     x,#4
                        djnz    y,#:par

                        test    stat,#8         wc      'if reset flag, transmit reset command
        if_c            mov     data,#$FF
        if_c            call    #transmit
'
'
' Get scancode
'
newcode                 mov     stat,#0                 'reset state

:same                   call    #receive                'receive byte from keyboard

                        cmp     data,#$AA       wz      'powerup/reset?
        if_z            jmp     #configure

                        cmp     data,#$E0       wz      'extended?
        if_z            or      stat,#1
        if_z            jmp     #:same

                        cmp     data,#$F0       wz      'released?
        if_z            or      stat,#2
        if_z            jmp     #:same

                        cmp     data,#$83+1     wc      'scancode?
        if_nc           jmp     #newcode                'unknown, ignore
'
'
' Translate scancode and enter into buffer
'
                        test    stat,#1         wc      'lookup code with extended flag
                        rcl     data,#1
                        call    #look

                        cmp     data,#0         wz      'if unknown, ignore
        if_z            jmp     #newcode

                        mov     t,_states+6             'remember lock keys in _states

                        mov     x,data                  'set/clear key bit in _states
                        shr     x,#5
                        add     x,#_states
                        movd    :reg,x
                        mov     y,#1
                        shl     y,data
                        test    stat,#2         wc
:reg                    muxnc   0,y

        if_nc           cmpsub  data,#$E1       wc      'if released or shift/ctrl/alt/win, done
        if_c            jmp     #update

                        cmpsub  data,#$DD       wc      'handle scrlock/capslock/numlock
        if_c            mov     x,#%001_000
        if_c            shl     x,data
        if_c            andn    x,_locks
        if_c            shr     x,#3
        if_c            shr     t,#29                   'ignore auto-repeat
        if_c            andn    x,t             wz
        if_c            xor     _locks,x
        if_c            add     data,#$DD
        if_c_and_nz     or      stat,#4                 'if change, set configure flag to update leds

                        test    y,#%11          wz      'get shift into nz

                        rdlong  x,par                   'if room in buffer and key valid, enter
                        sub     x,#1
                        and     x,#$F
                        cmp     x,_head         wz
        if_nz           test    data,#$FF       wz
        if_nz           mov     x,par
        if_nz           add     x,#11*4
        if_nz           add     x,_head
        if_nz           add     x,_head
        if_nz           wrword  data,x
        if_nz           add     _head,#1
        if_nz           and     _head,#$F

                        test    stat,#4         wc      'if not configure flag, done
        if_nc           jmp     #update                 'else configure to update leds
'
'
' Configure keyboard
'
configure               mov     data,#$F3               'set keyboard auto-repeat
                        call    #transmit
                        mov     data,_auto
                        and     data,#%11_11111
                        call    #transmit

                        mov     data,#$ED               'set keyboard lock-leds
                        call    #transmit
                        mov     data,_locks
                        rev     data,#-3 & $1F
                        test    data,#%100      wc
                        rcl     data,#1
                        and     data,#%111
                        call    #transmit

                        mov     x,_locks                'insert locks into _states
                        and     x,#%111
                        shl     _states+7,#3
                        or      _states+7,x
                        ror     _states+7,#3

                        mov     _present,#1             'set _present

                        jmp     #update                 'done
'
'
' Lookup byte in table
'
look
                        ror     data,#2                 'perform lookup
                        movs    :reg,data
                        add     :reg,#table
                        shr     data,#27
                        mov     x,data
:reg                    mov     data,0
                        shr     data,x

                        jmp     #rand                   'isolate byte
'
'
' Transmit byte to keyboard
'
transmit
_c1                     or      dira,cmask              'pull clock low
                        movs    napshr,#13              'hold clock for ~128us (must be >100us)
                        call    #nap
_d1                     or      dira,dmask              'pull data low
                        movs    napshr,#18              'hold data for ~4us
                        call    #nap
_c2                     xor     dira,cmask              'release clock

                        test    data,#$0FF      wc      'append parity and stop bits to byte
                        muxnc   data,#$100
                        or      data,dlsb

                        mov     x,#10                   'ready 10 bits
transmit_bit            call    #wait_c0                'wait until clock low
                        shr     data,#1         wc      'output data bit
_d2                     muxnc   dira,dmask
                        mov     wcond,c1                'wait until clock high
                        call    #wait
                        djnz    x,#transmit_bit         'another bit?

                        mov     wcond,c0d0              'wait until clock and data low
                        call    #wait
                        mov     wcond,c1d1              'wait until clock and data high
                        call    #wait

                        call    #receive_ack            'receive ack byte with timed wait
                        cmp     data,#$FA       wz      'if ack error, reset keyboard
        if_nz           jmp     #reset

transmit_ret            ret
'
'
' Receive byte from keyboard
'
receive                 test    _cpin,#$20      wc      'wait indefinitely for initial clock low
                        waitpne cmask,cmask
receive_ack
                        mov     x,#11                   'ready 11 bits
receive_bit             call    #wait_c0                'wait until clock low
                        movs    napshr,#16              'pause ~16us
                        call    #nap
_d3                     test    dmask,ina       wc      'input data bit
                        rcr     data,#1
                        mov     wcond,c1                'wait until clock high
                        call    #wait
                        djnz    x,#receive_bit          'another bit?

                        shr     data,#22                'align byte
                        test    data,#$1FF      wc      'if parity error, reset keyboard
        if_nc           jmp     #reset
rand                    and     data,#$FF               'isolate byte

look_ret
receive_ack_ret
receive_ret             ret
'
'
' Wait for clock/data to be in required state(s)
'
wait_c0                 mov     wcond,c0                '(wait until clock low)

wait                    mov     y,tenms                 'set timeout to 10ms

wloop                   movs    napshr,#18              'nap ~4us
                        call    #nap
_c3                     test    cmask,ina       wc      'check required state(s)
_d4                     test    dmask,ina       wz      'loop until got state(s) or timeout
wcond   if_never        djnz    y,#wloop                '(replaced with c0/c1/c0d0/c1d1)

                        tjz     y,#reset                'if timeout, reset keyboard
wait_ret
wait_c0_ret             ret


c0      if_c            djnz    y,#wloop                '(if_never replacements)
c1      if_nc           djnz    y,#wloop
c0d0    if_c_or_nz      djnz    y,#wloop
c1d1    if_nc_or_z      djnz    y,#wloop
'
'
' Nap
'
nap                     rdlong  t,#0                    'get clkfreq
napshr                  shr     t,#18/16/13             'shr scales time
                        min     t,#3                    'ensure waitcnt won't snag
                        add     t,cnt                   'add cnt to time
                        waitcnt t,#0                    'wait until time elapses (nap)

nap_ret                 ret
'
'
' Initialized data
'
'
dlsb                    long    1 << 9
tenms                   long    10_000 / 4
'
'
' Lookup table
'                               ascii   scan    extkey  regkey  ()=keypad
'
table                   word    $0000   '00
                        word    $0042   '01             F9
                        word    $0000   '02
                        word    $003E   '03             F5
                        word    $003C   '04             F3
                        word    $003A   '05             F1
                        word    $003B   '06             F2
                        word    $0045   '07             F12
                        word    $0000   '08
                        word    $0043   '09             F10
                        word    $0041   '0A             F8
                        word    $003F   '0B             F6
                        word    $003D   '0C             F4
                        word    $002B   '0D             Tab
                        word    $0035   '0E             `
                        word    $0000   '0F
                        word    $0000   '10
                        word    $E6E2   '11     Alt-R   Alt-L
                        word    $00E1   '12             Shift-L
                        word    $0000   '13
                        word    $E4E0   '14     Ctrl-R  Ctrl-L
                        word    $0014   '15             q
                        word    $001E   '16             1
                        word    $0000   '17
                        word    $0000   '18
                        word    $0000   '19
                        word    $001D   '1A             z
                        word    $0016   '1B             s
                        word    $0004   '1C             a
                        word    $001A   '1D             w
                        word    $001F   '1E             2
                        word    $E300   '1F     Win-L
                        word    $0000   '20
                        word    $0006   '21             c
                        word    $001B   '22             x
                        word    $0007   '23             d
                        word    $0008   '24             e
                        word    $0021   '25             4
                        word    $0020   '26             3
                        word    $E700   '27     Win-R
                        word    $0000   '28
                        word    $002C   '29             Space
                        word    $0019   '2A             v
                        word    $0009   '2B             f
                        word    $0017   '2C             t
                        word    $0015   '2D             r
                        word    $0022   '2E             5
                        word    $CC00   '2F     Apps
                        word    $0000   '30
                        word    $0011   '31             n
                        word    $0005   '32             b
                        word    $000B   '33             h
                        word    $000A   '34             g
                        word    $001C   '35             y
                        word    $0023   '36             6
                        word    $0000   '37     Power
                        word    $0000   '38
                        word    $0000   '39
                        word    $0010   '3A             m
                        word    $000D   '3B             j
                        word    $0018   '3C             u
                        word    $0024   '3D             7
                        word    $0025   '3E             8
                        word    $0000   '3F     Sleep
                        word    $0000   '40
                        word    $0036   '41             ,
                        word    $000E   '42             k
                        word    $000C   '43             i
                        word    $0012   '44             o
                        word    $0027   '45             0
                        word    $0026   '46             9
                        word    $0000   '47
                        word    $0000   '48
                        word    $0037   '49             .
                        word    $5438   '4A     (/)     /
                        word    $000F   '4B             l
                        word    $0033   '4C             ;
                        word    $0013   '4D             p
                        word    $002D   '4E             -
                        word    $0000   '4F
                        word    $0000   '50
                        word    $0000   '51
                        word    $0034   '52             '
                        word    $0000   '53
                        word    $002F   '54             [
                        word    $002E   '55             =
                        word    $0000   '56
                        word    $0000   '57
                        word    $00DE   '58             CapsLock
                        word    $00E5   '59             Shift-R
                        word    $5828   '5A     (Enter) Enter
                        word    $0030   '5B             ]
                        word    $0000   '5C
                        word    $0031   '5D             \
                        word    $0000   '5E     WakeUp
                        word    $0000   '5F
                        word    $0000   '60
                        word    $0064   '61
                        word    $0000   '62
                        word    $0000   '63
                        word    $0000   '64
                        word    $0000   '65
                        word    $002A   '66             BackSpace
                        word    $0000   '67
                        word    $0000   '68
                        word    $4D59   '69     End     (1)
                        word    $0000   '6A
                        word    $505C   '6B     Left    (4)
                        word    $4A5F   '6C     Home    (7)
                        word    $0000   '6D
                        word    $0000   '6E
                        word    $0000   '6F
                        word    $4962   '70     Insert  (0)
                        word    $4C63   '71     Delete  (.)
                        word    $515A   '72     Down    (2)
                        word    $005D   '73             (5)
                        word    $4F5E   '74     Right   (6)
                        word    $5260   '75     Up      (8)
                        word    $0029   '76             Esc
                        word    $00DF   '77             NumLock
                        word    $0044   '78             F11
                        word    $0057   '79             (+)
                        word    $4E5B   '7A     PageDn  (3)
                        word    $0056   '7B             (-)
                        word    $4655   '7C     PrScr   (*)
                        word    $4B61   '7D     PageUp  (9)
                        word    $00DD   '7E             ScrLock
                        word    $0000   '7F
                        word    $0000   '80
                        word    $0000   '81
                        word    $0000   '82
                        word    $0040   '83             F7
'
'
' Uninitialized data
'
dmask                   res     1
cmask                   res     1
stat                    res     1
data                    res     1
x                       res     1
y                       res     1
t                       res     1

_head                   res     1       'write-only
_present                res     1       'write-only
_states                 res     8       'write-only
_dpin                   res     1       'read-only at start
_cpin                   res     1       'read-only at start
_locks                  res     1       'read-only at start
_auto                   res     1       'read-only at start
''
'' Note: Driver will buffer up to 15 keystrokes, then ignore overflow.
