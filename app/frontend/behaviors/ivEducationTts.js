/**
 * 教學頁：語音朗讀（TTS）控制。
 *
 * 稽核 H-3：原本內嵌在 app/components/iv_analysis/education_component.rb 的 heredoc 裡。
 * 這裡是「逐字搬移」——行為完全不變，只是離開 Ruby 字串、進到 Vite 打包與 ESLint 覆蓋範圍。
 * TODO：型別化成 .ts（strict 模式下這批共約 600 個「可能是 null」與隱含 any 要處理）。
 */

export function init() {
  (function () {
    var TTS_URL     = 'http://127.0.0.1:5051/tts';
    var currentAudio = null;

    var volEl    = document.getElementById('tts-volume');
    var settBtn  = document.getElementById('tts-settings-btn');
    var settPane = document.getElementById('tts-settings-panel');
    var maleEl   = document.getElementById('tts-male-voice');
    var femaleEl = document.getElementById('tts-female-voice');

    // ── Volume ────────────────────────────────────────────────────
    var vol = parseFloat(localStorage.getItem('tts_volume') || '1.0');
    if (volEl) {
      volEl.value = vol;
      volEl.addEventListener('input', function () {
        vol = parseFloat(this.value);
        localStorage.setItem('tts_volume', String(vol));
      });
    }

    // ── Settings panel ─────────────────────────────────────────────
    if (settBtn && settPane) {
      settBtn.addEventListener('click', function () {
        settPane.classList.toggle('hidden');
      });
    }

    // ── Kokoro voice lists ────────────────────────────────────────
    var MALE_VOICES = [
      ['am_michael', 'Michael（美式男聲）'],
      ['am_adam',    'Adam（美式男聲）'],
      ['am_echo',    'Echo（美式男聲）'],
      ['am_eric',    'Eric（美式男聲）'],
      ['am_liam',    'Liam（美式男聲）'],
      ['am_onyx',    'Onyx（美式男聲）'],
      ['am_puck',    'Puck（美式男聲）'],
      ['bm_george',  'George（英式男聲）'],
      ['bm_daniel',  'Daniel（英式男聲）'],
      ['bm_fable',   'Fable（英式男聲）'],
    ];
    var FEMALE_VOICES = [
      ['af_sarah',   'Sarah（美式女聲）'],
      ['af_heart',   'Heart（美式女聲）'],
      ['af_bella',   'Bella（美式女聲）'],
      ['af_nicole',  'Nicole（美式女聲）'],
      ['af_nova',    'Nova（美式女聲）'],
      ['af_sky',     'Sky（美式女聲）'],
      ['af_jessica', 'Jessica（美式女聲）'],
      ['bf_emma',    'Emma（英式女聲）'],
      ['bf_alice',   'Alice（英式女聲）'],
      ['bf_lily',    'Lily（英式女聲）'],
    ];

    var maleVoice  = localStorage.getItem('kokoro_male_voice')  || 'am_michael';
    var femaleVoice = localStorage.getItem('kokoro_female_voice') || 'af_sarah';

    function populate(sel, voices, current) {
      if (!sel) return;
      sel.innerHTML = '';
      voices.forEach(function (v) {
        sel.appendChild(new Option(v[1], v[0], false, v[0] === current));
      });
    }
    populate(maleEl,   MALE_VOICES,   maleVoice);
    populate(femaleEl, FEMALE_VOICES, femaleVoice);

    if (maleEl) {
      maleEl.addEventListener('change', function () {
        maleVoice = this.value;
        localStorage.setItem('kokoro_male_voice', maleVoice);
      });
    }
    if (femaleEl) {
      femaleEl.addEventListener('change', function () {
        femaleVoice = this.value;
        localStorage.setItem('kokoro_female_voice', femaleVoice);
      });
    }

    // ── Speak via Kokoro local server ─────────────────────────────
    function speak(text, gender) {
      if (currentAudio) { currentAudio.pause(); currentAudio = null; }
      var voice = gender === 'male' ? maleVoice : femaleVoice;
      var url   = TTS_URL + '?text=' + encodeURIComponent(text) + '&voice=' + encodeURIComponent(voice);
      var audio = new Audio(url);
      audio.volume = vol;
      audio.play().catch(function (e) {
        console.warn('Kokoro TTS unavailable:', e.message,
          '— make sure pm2 kokoro-tts is running on port 5051');
      });
      currentAudio = audio;
    }

    window.ttsSpeak = speak;

    // ── Wire TTS buttons ──────────────────────────────────────────
    document.querySelectorAll('.tts-btn').forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        speak(btn.dataset.ttsText, btn.dataset.ttsGender);
      });
    });
  })();
}
