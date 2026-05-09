const imageInput = document.getElementById("imageInput");
const uploadForm = document.getElementById("uploadForm");
const analyzeButton = document.getElementById("analyzeButton");
const previewImage = document.getElementById("previewImage");
const dropText = document.getElementById("dropText");
const modelStatus = document.getElementById("modelStatus");
const categoryBadge = document.getElementById("categoryBadge");
const recommendation = document.getElementById("recommendation");
const briefReason = document.getElementById("briefReason");
const disclaimer = document.getElementById("disclaimer");
const rawOutput = document.getElementById("rawOutput");
const errorBox = document.getElementById("errorBox");

let selectedFile = null;

function setError(message) {
  errorBox.hidden = false;
  errorBox.textContent = message;
}

function clearError() {
  errorBox.hidden = true;
  errorBox.textContent = "";
}

function setBadge(category) {
  categoryBadge.className = "badge";
  if (category === "refer_for_clinical_review") {
    categoryBadge.classList.add("refer");
    categoryBadge.textContent = "Refer";
  } else if (category === "low_risk_or_variation") {
    categoryBadge.classList.add("low");
    categoryBadge.textContent = "Low risk";
  } else {
    categoryBadge.classList.add("muted");
    categoryBadge.textContent = "No result";
  }
}

function setBusy(isBusy) {
  analyzeButton.disabled = isBusy || selectedFile === null;
  analyzeButton.textContent = isBusy ? "Analyzing" : "Analyze";
}

async function loadStatus() {
  const response = await fetch("/api/status");
  const status = await response.json();
  const loaded = status.model_loaded ? "loaded" : "not loaded";
  const device = status.device || "CUDA unavailable";
  modelStatus.textContent = `${loaded} | ${device} | ${status.model_dir}`;
}

imageInput.addEventListener("change", () => {
  clearError();
  selectedFile = imageInput.files[0] || null;
  analyzeButton.disabled = selectedFile === null;
  if (selectedFile === null) {
    previewImage.style.display = "none";
    previewImage.removeAttribute("src");
    dropText.textContent = "Select oral crop image";
    return;
  }

  previewImage.src = URL.createObjectURL(selectedFile);
  previewImage.style.display = "block";
  dropText.textContent = selectedFile.name;
  setBadge(null);
});

uploadForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  clearError();

  if (selectedFile === null) {
    setError("No image selected.");
    return;
  }

  setBusy(true);
  const formData = new FormData();
  formData.append("file", selectedFile);

  const response = await fetch("/api/analyze", {
    method: "POST",
    body: formData,
  });
  const payload = await response.json();

  if (!response.ok) {
    setError(`${payload.error || "Error"}: ${payload.message || payload.detail || "Request failed"}`);
    rawOutput.textContent = payload.message || "";
    setBusy(false);
    return;
  }

  const result = payload.result;
  setBadge(result.category);
  recommendation.textContent = result.recommendation;
  briefReason.textContent = result.brief_reason;
  disclaimer.textContent = result.disclaimer;
  rawOutput.textContent = payload.raw_text;
  setBusy(false);
  await loadStatus();
});

loadStatus();
