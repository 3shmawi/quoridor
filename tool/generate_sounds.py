# Usage: python3 tool/generate_sounds.py assets/sounds
# Synthesises the game's sound effects: 16-bit mono 44.1 kHz WAV, no leading
# silence, short tails.
import math, random, struct, wave, sys, os
SR = 44100
out = sys.argv[1]
random.seed(7)

def write(name, samples):
    peak = max(abs(s) for s in samples) or 1
    samples = [s / peak * 0.8 for s in samples]
    # 2 ms fade in, 15 ms fade out: no clicks at either end.
    fi, fo = int(SR*0.002), int(SR*0.015)
    for i in range(fi): samples[i] *= i/fi
    for i in range(fo): samples[-1-i] *= i/fo
    with wave.open(os.path.join(out, name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(s*32767)) for s in samples))

def lowpass(xs, a):
    y = 0; r = []
    for x in xs: y += a*(x-y); r.append(y)
    return r

def tok(f, dur=0.12):
    # Wooden knock: a pitch-dropping sine body plus a short click.
    n = int(SR*dur); noise = lowpass([random.uniform(-1,1) for _ in range(n)], 0.35)
    ph = 0; r = []
    for i in range(n):
        t = i/SR
        ph += 2*math.pi*f*(1+0.6*math.exp(-t*60))/SR
        body = math.sin(ph)*math.exp(-t*38) + 0.35*math.sin(2.01*ph)*math.exp(-t*70)
        click = noise[i]*math.exp(-t*350)*0.8
        r.append(body+click)
    return r

def thud(f, dur=0.22):
    # A wall set down: low body, a gritty slide, a short rattle.
    n = int(SR*dur); noise = lowpass([random.uniform(-1,1) for _ in range(n)], 0.15)
    ph = 0; r = []
    for i in range(n):
        t = i/SR
        ph += 2*math.pi*f*(1+0.4*math.exp(-t*40))/SR
        body = math.sin(ph)*math.exp(-t*22)
        grit = noise[i]*math.exp(-t*45)*1.2
        r.append(body+grit)
    return r

def bell(f, dur):
    n = int(SR*dur); r = []
    for i in range(n):
        t = i/SR
        r.append((math.sin(2*math.pi*f*t) + 0.4*math.sin(2*math.pi*2*f*t)*math.exp(-t*6)
                  + 0.2*math.sin(2*math.pi*3.01*f*t)*math.exp(-t*9))*math.exp(-t*4.5))
    return r

for seat, f in zip(range(1,5), [520, 440, 620, 370]):
    write(f'move_{seat}.wav', tok(f))
for seat, f in zip(range(1,5), [200, 170, 235, 150]):
    write(f'wall_{seat}.wav', thud(f))

notes = [523.25, 659.25, 783.99, 1046.5]
total = int(SR*1.2); mix = [0.0]*total
for k, f in enumerate(notes):
    start = int(SR*0.11*k); b = bell(f, 1.2 - 0.11*k)
    for i, v in enumerate(b):
        if start+i < total: mix[start+i] += v*(0.8 if k < 3 else 1.0)
write('win.wav', mix)
