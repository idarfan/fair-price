/**
 * 教學頁：語音朗讀（TTS）控制。
 *
 * 稽核 H-3：原本內嵌在 app/components/iv_analysis/education_component.rb 的 heredoc 裡。
 * 音訊來自本機 Kokoro TTS server（pm2 kokoro-tts，port 5051）。
 */

type VoiceOption = readonly [value: string, label: string];

const TTS_URL = "http://127.0.0.1:5051/tts";

const MALE_VOICES: readonly VoiceOption[] = [
  ["am_michael", "Michael（美式男聲）"],
  ["am_adam", "Adam（美式男聲）"],
  ["am_echo", "Echo（美式男聲）"],
  ["am_eric", "Eric（美式男聲）"],
  ["am_liam", "Liam（美式男聲）"],
  ["am_onyx", "Onyx（美式男聲）"],
  ["am_puck", "Puck（美式男聲）"],
  ["bm_george", "George（英式男聲）"],
  ["bm_daniel", "Daniel（英式男聲）"],
  ["bm_fable", "Fable（英式男聲）"],
];

const FEMALE_VOICES: readonly VoiceOption[] = [
  ["af_sarah", "Sarah（美式女聲）"],
  ["af_heart", "Heart（美式女聲）"],
  ["af_bella", "Bella（美式女聲）"],
  ["af_nicole", "Nicole（美式女聲）"],
  ["af_nova", "Nova（美式女聲）"],
  ["af_sky", "Sky（美式女聲）"],
  ["af_jessica", "Jessica（美式女聲）"],
  ["bf_emma", "Emma（英式女聲）"],
  ["bf_alice", "Alice（英式女聲）"],
  ["bf_lily", "Lily（英式女聲）"],
];

export function init(): void {
  let currentAudio: HTMLAudioElement | null = null;

  const volEl = document.getElementById("tts-volume");
  const settBtn = document.getElementById("tts-settings-btn");
  const settPane = document.getElementById("tts-settings-panel");
  const maleEl = document.getElementById("tts-male-voice");
  const femaleEl = document.getElementById("tts-female-voice");

  // ── 音量 ──────────────────────────────────────────────────────
  let vol = parseFloat(localStorage.getItem("tts_volume") || "1.0");
  if (volEl instanceof HTMLInputElement) {
    volEl.value = String(vol);
    volEl.addEventListener("input", () => {
      vol = parseFloat(volEl.value);
      localStorage.setItem("tts_volume", String(vol));
    });
  }

  // ── 設定面板 ───────────────────────────────────────────────────
  if (settBtn && settPane) {
    settBtn.addEventListener("click", () => {
      settPane.classList.toggle("hidden");
    });
  }

  // ── Kokoro 音色清單 ────────────────────────────────────────────
  let maleVoice = localStorage.getItem("kokoro_male_voice") || "am_michael";
  let femaleVoice = localStorage.getItem("kokoro_female_voice") || "af_sarah";

  function populate(
    sel: HTMLElement | null, voices: readonly VoiceOption[], current: string,
  ): void {
    if (!(sel instanceof HTMLSelectElement)) return;
    sel.innerHTML = "";
    voices.forEach(([value, label]) => {
      sel.appendChild(new Option(label, value, false, value === current));
    });
  }
  populate(maleEl, MALE_VOICES, maleVoice);
  populate(femaleEl, FEMALE_VOICES, femaleVoice);

  if (maleEl instanceof HTMLSelectElement) {
    maleEl.addEventListener("change", () => {
      maleVoice = maleEl.value;
      localStorage.setItem("kokoro_male_voice", maleVoice);
    });
  }
  if (femaleEl instanceof HTMLSelectElement) {
    femaleEl.addEventListener("change", () => {
      femaleVoice = femaleEl.value;
      localStorage.setItem("kokoro_female_voice", femaleVoice);
    });
  }

  // ── 透過本機 Kokoro server 朗讀 ────────────────────────────────
  function speak(text: string, gender: string): void {
    if (currentAudio) { currentAudio.pause(); currentAudio = null; }
    const voice = gender === "male" ? maleVoice : femaleVoice;
    const url = `${TTS_URL}?text=${encodeURIComponent(text)}&voice=${encodeURIComponent(voice)}`;
    const audio = new Audio(url);
    audio.volume = vol;
    audio.play().catch((e: unknown) => {
      const message = e instanceof Error ? e.message : String(e);
      console.warn("Kokoro TTS unavailable:", message,
        "— make sure pm2 kokoro-tts is running on port 5051");
    });
    currentAudio = audio;
  }

  window.ttsSpeak = speak;

  // ── 綁定朗讀按鈕 ───────────────────────────────────────────────
  document.querySelectorAll<HTMLElement>(".tts-btn").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      // 型別化前這裡直接傳 dataset 值（可能是 undefined）；缺任一個就跳過，
      // 避免朗讀出字面上的 "undefined"。
      const text = btn.dataset["ttsText"];
      const gender = btn.dataset["ttsGender"];
      if (text === undefined || gender === undefined) return;
      speak(text, gender);
    });
  });
}
