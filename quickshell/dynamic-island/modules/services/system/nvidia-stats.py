"""Nur Messwerte der GTX 1650, niemals AMD-Werte als NVIDIA ausgeben."""
import csv
import subprocess
import sys

def main():
    try:
        result = subprocess.run([
            'nvidia-smi',
            '--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total',
            '--format=csv,noheader,nounits',
        ], capture_output=True, text=True, timeout=1.5, check=True)
        rows = csv.reader(result.stdout.splitlines(), skipinitialspace=True)
        row = next(r for r in rows if 'GTX 1650' in r[0])
        name, busy, temp, used, total = row
        busy, temp, used, total = map(float, (busy, temp, used, total))
        print('N', name.strip())
        print('G busy', busy)
        print('T gpu', temp * 1000)
        print('G vram', int(used * 1048576), int(total * 1048576))
    except (OSError, ValueError, StopIteration, subprocess.SubprocessError) as exc:
        print('NVIDIA-Messung nicht verfuegbar:', exc, file=sys.stderr)

if __name__ == '__main__':
    main()
