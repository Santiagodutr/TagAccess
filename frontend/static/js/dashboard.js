document.addEventListener("DOMContentLoaded", () => {
  const banner = document.querySelector(".banner--error");
  if (banner) {
    setTimeout(() => {
      banner.classList.add("is-hidden");
    }, 8000);
  }

  const blockForms = document.querySelectorAll(".table-action");
  blockForms.forEach((form) => {
    const blockButton = form.querySelector(".block-btn");
    if (!blockButton) {
      return;
    }

    blockButton.addEventListener("click", () => {
      const student = form.dataset.student || "este usuario";
      const room = form.dataset.room || "el salón";
      const confirmation = window.confirm(
        `¿Bloquear el acceso de ${student} al salón ${room}?`
      );

      if (!confirmation) {
        return;
      }

      const reasonField = form.querySelector('input[name="reason"]');
      if (reasonField) {
        const providedReason = window.prompt(
          "Motivo del bloqueo (opcional):"
        );
        reasonField.value = providedReason ? providedReason.trim() : "";
      }

      form.submit();
    });
  });
});
