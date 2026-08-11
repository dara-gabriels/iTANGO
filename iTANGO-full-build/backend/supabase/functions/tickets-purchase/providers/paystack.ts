// supabase/functions/tickets-purchase/providers/paystack.ts

interface InitParams {
  email: string;
  amountKobo: number;
  reference: string; // our internal payments.id — becomes provider_reference on the webhook side
  callbackUrl: string;
}

export async function initializePaystackTransaction(params: InitParams): Promise<string> {
  const response = await fetch("https://api.paystack.co/transaction/initialize", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("PAYSTACK_SECRET_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email: params.email,
      amount: params.amountKobo,
      reference: params.reference,
      callback_url: params.callbackUrl,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Paystack initialize failed (${response.status}): ${body}`);
  }

  const data = await response.json();
  return data.data.authorization_url as string;
}
