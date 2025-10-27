import 'package:flutter/material.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  int credits = 10;

  void _earnCredits() {
    setState(() => credits += 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You earned 1 credit!')),
    );
  }

  void _buyCredits() {
    setState(() => credits += 20);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Credits')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Your Credits: $credits', style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.video_call),
              label: const Text('Watch Ad to Earn'),
              onPressed: _earnCredits,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_card),
              label: const Text('Buy 20 Credits'),
              onPressed: _buyCredits,
            ),
          ],
        ),
      ),
    );
  }
}
