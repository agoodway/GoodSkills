# JavaScript Hook Reference

## StripePaymentElement Hook

Add this hook to `assets/js/app.js`. Register it with the LiveSocket.

```javascript
const StripePaymentElement = {
  mounted() {
    this.publishableKey = this.el.dataset.publishableKey
    this.returnUrl = this.el.dataset.returnUrl
    this.stripe = null
    this.elements = null
    this.paymentElement = null

    this.paymentElementContainer = this.el.querySelector("[data-role='payment-element']")
    this.confirmButton = this.el.querySelector("[data-role='confirm-payment']")
    this.errorElement = this.el.querySelector("[data-role='payment-error']")

    this.onConfirmPayment = (event) => this.confirmPayment(event)
    this.confirmButton?.addEventListener("click", this.onConfirmPayment)

    this.handleEvent("stripe:client_secret", ({client_secret}) => {
      this.mountPaymentElement(client_secret)
    })
  },

  destroyed() {
    this.confirmButton?.removeEventListener("click", this.onConfirmPayment)
    this.paymentElement?.unmount()
  },

  loadStripeJs() {
    if (window.Stripe) return Promise.resolve()
    if (this._stripePromise) return this._stripePromise

    this._stripePromise = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = "https://js.stripe.com/v3/"
      script.onload = resolve
      script.onerror = () => reject(new Error("Failed to load Stripe.js"))
      document.head.appendChild(script)
    })

    return this._stripePromise
  },

  async mountPaymentElement(clientSecret) {
    if (!clientSecret || !this.paymentElementContainer) return

    if (!this.publishableKey) {
      this.setError("Stripe publishable key is not configured.")
      return
    }

    try {
      await this.loadStripeJs()
    } catch (_e) {
      this.setError("Stripe.js failed to load. Refresh and try again.")
      return
    }

    this.paymentElement?.unmount()
    this.stripe = window.Stripe(this.publishableKey)
    this.elements = this.stripe.elements({clientSecret})
    this.paymentElement = this.elements.create("payment")
    this.paymentElement.mount(this.paymentElementContainer)
    this.setError("")
  },

  async confirmPayment(event) {
    event.preventDefault()

    if (!this.stripe || !this.elements) {
      this.setError("Select a pack first to initialize checkout.")
      return
    }

    this.confirmButton?.setAttribute("disabled", "disabled")

    const {error} = await this.stripe.confirmPayment({
      elements: this.elements,
      confirmParams: {return_url: this.returnUrl},
    })

    if (error) {
      this.setError(error.message || "Payment could not be completed.")
      this.confirmButton?.removeAttribute("disabled")
    }
  },

  setError(message) {
    if (!this.errorElement) return
    this.errorElement.textContent = message || ""
  },
}
```

### Registration

Add to the hooks object in `app.js`:

```javascript
const hooks = {...existingHooks, StripePaymentElement}
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks,
})
```

### How It Works

1. **Lazy loading**: Stripe.js is loaded from CDN only when a pack is selected (not on page load)
2. **Event-driven**: The LiveView pushes `stripe:client_secret` event after creating a PaymentIntent
3. **Payment Element**: Stripe's embedded payment form handles card input, validation, and 3DS
4. **Confirmation**: On pay button click, calls `stripe.confirmPayment()` which redirects to `return_url`
5. **Error handling**: Displays Stripe errors in the `[data-role="payment-error"]` element
6. **Cleanup**: Unmounts the payment element and removes event listeners on destroy

### Required HTML Structure

The hook expects these `data-role` attributes in the LiveView template:

```html
<div id="stripe-payment"
     phx-hook="StripePaymentElement"
     data-publishable-key={@stripe_publishable_key}
     data-return-url={@return_url}>
  <div data-role="payment-element" />
  <button data-role="confirm-payment">Pay</button>
  <p data-role="payment-error" />
</div>
```
