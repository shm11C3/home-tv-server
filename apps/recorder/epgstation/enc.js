// EPGStation のエンコードスクリプト。入力は EPGStation が設定する環境変数から読む
// GPU passthrough 後に compose の環境変数で ENCODER=nvenc にすると NVENC を使う
const { spawn } = require('child_process');

const ffmpeg = process.env.FFMPEG;
const input = process.env.INPUT;
const output = process.env.OUTPUT;
const isDual = process.env.ISDUALMONO === '1';
const useNvenc = process.env.ENCODER === 'nvenc';

const args = ['-y', '-analyzeduration', '10M', '-probesize', '32M'];
if (useNvenc) args.push('-hwaccel', 'cuda', '-hwaccel_output_format', 'cuda');
args.push('-fix_sub_duration', '-i', input);

// 映像
if (useNvenc) {
  args.push('-c:v', 'h264_nvenc', '-preset', 'p5', '-cq', '23', '-b:v', '0', '-vf', 'yadif_cuda');
} else {
  args.push('-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-vf', 'yadif');
}

// 音声
if (isDual) {
  args.push('-filter_complex', 'channelsplit[FL][FR]', '-map', '0:v', '-map', '[FL]', '-map', '[FR]',
    '-metadata:s:a:0', 'title=main', '-metadata:s:a:1', 'title=sub');
} else {
  args.push('-map', '0:v', '-map', '0:a');
}
args.push('-c:a', 'aac', '-ar', '48000', '-ab', '192k', '-ac', '2');

// 字幕はデータトラックとして mp4 に入れられないので落とす
args.push('-sn', '-movflags', '+faststart', '-f', 'mp4', output);

const child = spawn(ffmpeg, args);
child.stderr.on('data', (d) => process.stderr.write(d));
child.on('error', (err) => { console.error(err); process.exit(1); });
child.on('exit', (code) => process.exit(code ?? 1));
