import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';

// The name of your DynamoDB table
const USER_TABLE_NAME = 'DeckUserPremissions'; 

// Initialize the modular AWS SDK v3 clients
// The DynamoDBDocumentClient simplifies operations (like the old DocumentClient)
const client = new DynamoDBClient({}); 
const docClient = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
    // Check for the Post Confirmation trigger event
    if (event.triggerSource === 'PostConfirmation_ConfirmSignUp') {
        
        // Extract required attributes from the Cognito event
        const userId = event.request.userAttributes.sub; 
        const email = event.request.userAttributes.email;
        const name = event.request.userAttributes.name || 'Anonymous User';

        console.log(`User confirmed. Creating profile for userId: ${userId}`);

        // Define the PutCommand parameters
        const params = {
            TableName: USER_TABLE_NAME,
            Item: {
                userId: userId, 
                email: email,
                displayName: name,
                createdAt: new Date().toISOString(),
                highScore: 0, 
                matchesPlayed: 0,
                permitted_decks: ['letter_deck']
            }
        };

        try {
            // Execute the write operation using the V3 modular command pattern
            await docClient.send(new PutCommand(params));
            console.log("Successfully wrote user profile to DynamoDB using SDK v3.");
            
            return event; 

        } catch (error) {
            console.error("Error writing user profile to DynamoDB:", error);
            // Must still return the event to prevent infinite retries by Cognito
            return event; 
        }
    }
    
    return event;
};

