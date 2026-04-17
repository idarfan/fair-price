# frozen_string_literal: true

class FairValue::FontSizeControlsComponent < ApplicationComponent
  SIZES = [
    { px: 14, idx: 0 },
    { px: 15, idx: 1 },
    { px: 16, idx: 2 },
    { px: 17, idx: 3 },
    { px: 18, idx: 4 }
  ].freeze
  STORAGE_KEY = "fairprice:font-size"

  def view_template
    div(class: "flex items-center gap-0.5", id: "font-size-controls") do
      SIZES.each do |s|
        button(
          type: "button",
          data: { size: s[:px] },
          title: "字體 #{s[:px]}px",
          class: "font-size-btn px-1 py-0.5 rounded transition-colors font-bold text-gray-400 hover:text-gray-700 hover:bg-gray-100 leading-none",
          style: "font-size: #{10 + s[:idx] * 2}px; line-height: 1.2;"
        ) { plain("A") }
      end
    end
    render_script
  end

  private

  def render_script
    script do
      raw <<~JS.html_safe
        (function() {
          var KEY = '#{STORAGE_KEY}';
          var ALLOWED = ['14','15','16','17','18'];
          var container = document.getElementById('font-size-controls');
          if (!container) return;
          var btns = container.querySelectorAll('.font-size-btn');

          function applySize(px) {
            document.documentElement.style.fontSize = px + 'px';
            localStorage.setItem(KEY, String(px));
            updateActive(String(px));
          }

          function updateActive(active) {
            btns.forEach(function(b) {
              var isActive = b.getAttribute('data-size') === active;
              b.classList.toggle('text-blue-600', isActive);
              b.classList.toggle('bg-blue-50', isActive);
              b.classList.toggle('text-gray-400', !isActive);
            });
          }

          var stored = localStorage.getItem(KEY);
          updateActive(ALLOWED.indexOf(stored) !== -1 ? stored : '16');

          btns.forEach(function(b) {
            b.addEventListener('click', function() {
              var s = b.getAttribute('data-size');
              if (ALLOWED.indexOf(s) !== -1) applySize(parseInt(s, 10));
            });
          });
        })();
      JS
    end
  end
end
