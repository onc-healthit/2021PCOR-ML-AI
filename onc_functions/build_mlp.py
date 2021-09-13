import tensorflow as tf
from tensorflow.keras.layers import Dense, Dropout
from tensorflow.keras.layers.experimental import preprocessing
from tensorflow.keras.wrappers.scikit_learn import KerasClassifier
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.constraints import max_norm
from tensorflow.keras.metrics import AUC
METRICS = [
      tf.keras.metrics.TruePositives(name='tp'),
      tf.keras.metrics.FalsePositives(name='fp'),
      tf.keras.metrics.TrueNegatives(name='tn'),
      tf.keras.metrics.FalseNegatives(name='fn'), 
      tf.keras.metrics.BinaryAccuracy(name='accuracy'),
      tf.keras.metrics.Precision(name='precision'),
      tf.keras.metrics.Recall(name='recall'),
      tf.keras.metrics.AUC(name='auc'),
      tf.keras.metrics.AUC(name='auc_pr',
            num_thresholds=200,
            curve="PR",
            summation_method="interpolation",
            dtype=None,
            thresholds=None,
            multi_label=False,
            label_weights=None)
]

def build_mlp(
    layers=2,
    neurons=16,
    output_bias=None, 
    optimizer='Adam',
    activation='relu',
    learn_rate=.0002,
    dropout_rate=0.2,
    kernel_regularizer='l2',
    metrics=METRICS
):
    if output_bias is not None:
        output_bias = tf.keras.initializers.Constant(output_bias)
    model = tf.keras.Sequential()
    for i in range(layers):
        model.add(Dense(
                            neurons, 
                            activation=activation,
                            input_shape=(294,),
                            kernel_regularizer=kernel_regularizer))
                                
    model.add(Dropout(dropout_rate))
    model.add(Dense(
                     1, 
                     activation='sigmoid',
                     bias_initializer=output_bias))
      
    opt = Adam(lr=learn_rate)
    
    model.compile(
      optimizer=opt,
      loss=tf.keras.losses.BinaryCrossentropy(),
      metrics=metrics)

    return model
